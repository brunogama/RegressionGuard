import Foundation

/// Where the command writes.
///
/// Stdout carries exactly what the chosen format promises, so a caller can pipe it. Everything
/// about the run's own completeness - evidence gaps, an under-selected grammar - goes to stderr,
/// where it cannot corrupt a parsed report but also cannot be missed.
enum Console {
  static func write(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }

  static func writeError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
}
