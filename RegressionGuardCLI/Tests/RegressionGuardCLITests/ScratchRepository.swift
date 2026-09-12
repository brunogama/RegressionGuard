import Foundation

/// A throwaway git repository and the built CLI run against it.
///
/// Shared by the suites that test the shipped binary rather than the library, which all need the
/// same four things: a repository, files in it, commits, and the guard's own report back.
struct ScratchRepository {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"])
    try git(["config", "user.email", "test@example.com"])
    try git(["config", "user.name", "Regression Guard Tests"])
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }

  func write(_ contents: String, to path: String) throws {
    let file = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: file, atomically: true, encoding: .utf8)
  }

  /// Stages everything, commits it, and returns the resulting SHA.
  @discardableResult
  func commit(_ message: String) throws -> String {
    try git(["add", "."])
    try git(["commit", "-q", "-m", message])
    return try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Runs `regression-guard check` and returns what it printed.
  ///
  /// - Parameter head: the ref to check, or `nil` to check the working tree.
  func check(base: String, head: String?, arguments: [String] = []) throws -> CommandResult {
    var invocation = ["check", "--base", base, "--path", url.path] + arguments
    if let head { invocation += ["--head", head] }
    return try Self.run(
      executable: Self.packageDirectory.appendingPathComponent(".build/debug/regression-guard"),
      arguments: invocation,
      directory: url
    )
  }

  /// The machine-readable report the same run wrote, which is where the evidence a finding was
  /// judged on is visible at all - the text output states findings and nothing about the run.
  func checkReport(base: String, head: String?) throws -> GuardReportFixture {
    let file = url.appendingPathComponent("report.json")
    _ = try check(base: base, head: head, arguments: ["--report-file", file.path])
    return try JSONDecoder().decode(GuardReportFixture.self, from: Data(contentsOf: file))
  }

  /// Runs the check with `git` replaced by a shim that records every invocation before execing the
  /// real one.
  ///
  /// The environment is set on the child rather than on this process, so nothing here depends on
  /// test ordering or isolation.
  ///
  /// - Returns: the arguments of each `git` the run made, in order.
  func gitInvocationsDuringCheck(base: String, head: String?) throws -> [String] {
    let shim = url.appendingPathComponent("shim")
    let log = url.appendingPathComponent("git-invocations.log")
    try FileManager.default.createDirectory(at: shim, withIntermediateDirectories: true)
    let script = shim.appendingPathComponent("git")
    try """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$REGRESSION_GUARD_TEST_GIT_LOG"
      exec /usr/bin/git "$@"

      """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = shim.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
    environment["REGRESSION_GUARD_TEST_GIT_LOG"] = log.path

    var invocation = ["check", "--base", base, "--path", url.path]
    if let head { invocation += ["--head", head] }
    _ = try Self.run(
      executable: Self.packageDirectory.appendingPathComponent(".build/debug/regression-guard"),
      arguments: invocation,
      directory: url,
      environment: environment
    )

    let recorded = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    return recorded.split(separator: "\n").map(String.init)
  }

  @discardableResult
  func git(_ arguments: [String]) throws -> String {
    try Self.run(
      executable: URL(fileURLWithPath: "/usr/bin/git"),
      arguments: arguments,
      directory: url
    ).output
  }

  static func run(
    executable: URL,
    arguments: [String],
    directory: URL,
    environment: [String: String]? = nil
  ) throws -> CommandResult {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardOutput = output
    process.standardError = output

    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let text = String(data: data, encoding: .utf8) else {
      throw CommandError.invalidUTF8Output
    }
    return CommandResult(status: process.terminationStatus, output: text)
  }

  /// The CLI package root, where `swift build` puts the binary under test.
  static var packageDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}

struct CommandResult {
  let status: Int32
  let output: String
}

enum CommandError: Error {
  case invalidUTF8Output
}

/// The report as a reader of the artifact sees it.
///
/// Decoded structurally rather than through `GuardReport` on purpose: this suite is checking what
/// the binary actually wrote, and sharing the type it wrote it with would make a field that never
/// reached the file indistinguishable from one that did.
struct GuardReportFixture: Decodable {
  struct Finding: Decodable {
    let ruleID: String
    let evidence: String?
  }

  struct Grammar: Decodable {
    let alignmentSeries: Int
  }

  struct Gap: Decodable {
    let path: String
    let ref: String
    let reason: String
  }

  let findings: [Finding]
  let syntaxGrammar: Grammar?
  let syntacticEvidenceGaps: [Gap]
}
