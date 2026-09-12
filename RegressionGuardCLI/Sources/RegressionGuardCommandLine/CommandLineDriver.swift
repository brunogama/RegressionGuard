import Commander
import Foundation

/// Turns a command body into a process: help, error reporting, and exit status.
///
/// Commander resolves and parses but never runs anything, so the step between "these are the
/// arguments" and "the process exited 1" belongs to the caller. Keeping it here means both
/// executables fail identically, and that `ExitCode.failure` still means exit 1 rather than a
/// crash on an uncaught error.
public enum CommandLineDriver {
  /// The tokens that mean "describe yourself instead of running".
  public static let helpFlags: Set<String> = ["--help", "-h", "help"]

  public static func wantsHelp(_ arguments: [String]) -> Bool {
    arguments.contains { helpFlags.contains($0) }
  }

  /// Runs `body`, then exits.
  ///
  /// `ExitCode` carries its own status because a command throws it to fail deliberately; every
  /// other error is a message on stderr and exit 1. Nothing propagates out as a crash, so a guard
  /// that fails still fails in a way CI can read.
  ///
  /// Main-actor isolated because Commander declares `ParsableCommand` that way, so every command
  /// this runs is already confined to it.
  @MainActor
  public static func run(_ body: @MainActor () async throws -> Void) async -> Never {
    do {
      try await body()
      exit(0)
    } catch let code as ExitCode {
      exit(code.rawValue)
    } catch let error as ValidationError {
      writeError("error: \(error.description)")
      exit(1)
    } catch let error as CommanderProgramError {
      writeError("error: \(error.description)")
      exit(1)
    } catch let error as CommanderError {
      writeError("error: \(error.description)")
      exit(1)
    } catch {
      writeError("error: \(error.localizedDescription)")
      exit(1)
    }
  }

  public static func writeError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }

  public static func write(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }
}
