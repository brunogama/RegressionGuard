import Foundation
import Testing

@Suite("Enforcement weakening end-to-end tests")
struct EnforcementWeakeningEndToEndTests {
  @Test("CLI blocks concrete guard-configuration weakenings")
  func cliBlocksConcreteGuardConfigurationWeakenings() throws {
    let repository = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repository) }

    try writeBaselineFiles(to: repository)
    try runGit(["add", "."], in: repository)
    try runGit(["commit", "-q", "-m", "Add guard configuration"], in: repository)
    let base = try revision(in: repository)

    try writeWeakenedFiles(to: repository)
    try runGit(["add", "."], in: repository)
    try runGit(["commit", "-q", "-m", "Relax guard configuration"], in: repository)
    let head = try revision(in: repository)

    let result = try runGuard(base: base, head: head, in: repository)

    #expect(result.status == 1)
    #expect(result.output.contains("enforcement_weakening"))
  }

  private func makeRepository() throws -> URL {
    let repository = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    try runGit(["init", "-q", "-b", "main"], in: repository)
    try runGit(["config", "user.email", "test@example.com"], in: repository)
    try runGit(["config", "user.name", "Regression Guard Tests"], in: repository)
    return repository
  }

  private func writeBaselineFiles(to repository: URL) throws {
    try write(
      """
      rules:
        disabled_or_skipped_test:
          enabled: true
      """,
      to: ".regressionguard.yml",
      in: repository
    )
    try write(
      """
      jobs:
        test:
          steps:
            - run: swift test
      """,
      to: ".github/workflows/ci.yml",
      in: repository
    )
    try write("disabled_rules: []\n", to: ".swiftlint.yml", in: repository)
    try write(
      "let package = Package(targets: [.testTarget(name: \"Tests\")])\n",
      to: "Package.swift",
      in: repository
    )
  }

  private func writeWeakenedFiles(to repository: URL) throws {
    try write(
      """
      rules:
        disabled_or_skipped_test:
          enabled: false
      """,
      to: ".regressionguard.yml",
      in: repository
    )
    try write(
      """
      jobs:
        test:
          steps:
            - run: swift build
      """,
      to: ".github/workflows/ci.yml",
      in: repository
    )
    try write(
      "disabled_rules:\n  - force_unwrapping\n",
      to: ".swiftlint.yml",
      in: repository
    )
    try write(
      "let package = Package(targets: [.target(name: \"Tests\")])\n",
      to: "Package.swift",
      in: repository
    )
  }

  private func write(_ contents: String, to path: String, in repository: URL) throws {
    let file = repository.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: file, atomically: true, encoding: .utf8)
  }

  private func runGuard(base: String, head: String, in repository: URL) throws -> CommandResult {
    try run(
      executable:
        projectDirectory
        .appendingPathComponent(".build/debug/regression-guard"),
      arguments: [
        "check", "--base", base, "--head", head, "--path", repository.path,
      ],
      directory: repository
    )
  }

  @discardableResult
  private func runGit(_ arguments: [String], in repository: URL) throws -> String {
    try run(
      executable: URL(fileURLWithPath: "/usr/bin/git"),
      arguments: arguments,
      directory: repository
    ).output
  }

  private func revision(in repository: URL) throws -> String {
    try runGit(["rev-parse", "HEAD"], in: repository)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func run(executable: URL, arguments: [String], directory: URL) throws -> CommandResult {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else {
      throw CommandError.invalidUTF8Output
    }
    return CommandResult(status: process.terminationStatus, output: text)
  }

  private var projectDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}

private struct CommandResult {
  let status: Int32
  let output: String
}

private enum CommandError: Error {
  case invalidUTF8Output
}
