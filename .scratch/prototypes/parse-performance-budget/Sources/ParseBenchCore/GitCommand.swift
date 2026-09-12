import Foundation

/// Runs `git` and counts every invocation.
///
/// The count is the budget's first clause, so it is taken from the one place that spawns rather
/// than from a tally of the call sites someone remembered to look at. Single-threaded on purpose:
/// concurrency is one of the things the harness is measuring the need for.
public enum GitCommand {
  /// Invocations since the last ``resetCount()``.
  public static var count: Int { state.withLock { $0 } }

  public static func resetCount() { state.withLock { $0 = 0 } }

  /// Runs `git` in `repo` and returns its standard output.
  ///
  /// A failed invocation is fatal rather than an empty result. The harness exists to publish
  /// numbers, and a spawn that silently returned nothing would be recorded as a very fast parse
  /// of zero bytes - a wrong number that looks like a good one, which is the exact shape of
  /// regression this repository is built to catch.
  ///
  /// - Parameters:
  ///   - arguments: the `git` arguments, without the leading `git`.
  ///   - repo: the working directory to run in.
  ///   - stdin: bytes to write to the process, for `cat-file --batch`.
  /// - Returns: the invocation's standard output.
  @discardableResult
  public static func run(_ arguments: [String], in repo: String, stdin: Data? = nil) -> Data {
    state.withLock { $0 += 1 }

    let process = Process()
    process.currentDirectoryURL = URL(fileURLWithPath: repo)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments

    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    let input = Pipe()
    if stdin != nil { process.standardInput = input }

    do {
      try process.run()
    } catch {
      fatalError("could not spawn git \(arguments.joined(separator: " ")): \(error)")
    }
    if let stdin {
      input.fileHandleForWriting.write(stdin)
      try? input.fileHandleForWriting.close()
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorText = String(
      decoding: errors.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      fatalError(
        "git \(arguments.joined(separator: " ")) failed "
          + "(\(process.terminationStatus)): \(errorText)"
      )
    }
    return data
  }

  private static let state = Mutex(0)
}
