import Foundation

public enum GitError: Error, CustomStringConvertible {
  case commandFailed(command: [String], status: Int32, stderr: String)

  public var description: String {
    switch self {
    case .commandFailed(let command, let status, let stderr):
      return "git \(command.joined(separator: " ")) failed (\(status)): \(stderr)"
    }
  }
}

/// Thin wrapper around shelling out to `git`. Kept dependency-free and synchronous: this tool
/// runs once per CI job, not in a hot loop.
public struct GitRepository {
  public let workingDirectory: URL

  public init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
  }

  @discardableResult
  public func run(_ arguments: [String]) throws -> String {
    let process = Process()
    process.currentDirectoryURL = workingDirectory
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw GitError.commandFailed(
        command: arguments,
        status: process.terminationStatus,
        stderr: String(data: errData, encoding: .utf8) ?? ""
      )
    }
    return String(data: outData, encoding: .utf8) ?? ""
  }

  /// Unified diff between two refs, or between a ref and the working tree when head is `nil`.
  public func diff(base: String, head: String?, context: Int = 3) throws -> String {
    var args = ["diff", "--no-color", "-U\(context)", base]
    if let head { args.append(head) }
    return try run(args)
  }

  /// Full content of `path` as it existed at `ref`. Returns `nil` if the path did not exist.
  public func show(ref: String, path: String) -> String? {
    try? run(["show", "\(ref):\(path)"])
  }

  /// Commit subjects and bodies in `base..head`, used to look for an approval marker.
  public func commitMessages(base: String, head: String) throws -> [String] {
    let output = try run(["log", "--format=%B%x1e", "\(base)..\(head)"])
    return
      output
      .components(separatedBy: "\u{1e}")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
