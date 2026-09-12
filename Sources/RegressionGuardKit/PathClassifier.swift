import Foundation

/// Classifies file paths as test code, ignored, or production code using the glob-ish patterns
/// from `Configuration`. Supports `*`, `**`, and literal segments - enough for typical
/// `Tests/**`, `**/*Tests.swift` style patterns without pulling in a full glob library.
public struct PathClassifier {
  public let testPatterns: [String]
  public let ignorePatterns: [String]

  public init(testPatterns: [String], ignorePatterns: [String]) {
    self.testPatterns = testPatterns
    self.ignorePatterns = ignorePatterns
  }

  public func isTestPath(_ path: String) -> Bool {
    testPatterns.contains { Self.matches(pattern: $0, path: path) }
  }

  public func isIgnored(_ path: String) -> Bool {
    ignorePatterns.contains { Self.matches(pattern: $0, path: path) }
  }

  public static func matches(pattern: String, path: String) -> Bool {
    let regex = globToRegex(pattern)
    guard let re = try? NSRegularExpression(pattern: regex) else { return false }
    let range = NSRange(path.startIndex..<path.endIndex, in: path)
    return re.firstMatch(in: path, range: range) != nil
  }

  /// Converts a limited glob syntax (`**`, `*`, literal) into an anchored regex.
  private static func globToRegex(_ pattern: String) -> String {
    var result = "^"
    var i = pattern.startIndex
    while i < pattern.endIndex {
      if pattern[i...].hasPrefix("**/") {
        result += "(?:.*/)?"
        i = pattern.index(i, offsetBy: 3)
      } else if pattern[i...].hasPrefix("**") {
        result += ".*"
        i = pattern.index(i, offsetBy: 2)
      } else if pattern[i] == "*" {
        result += "[^/]*"
        i = pattern.index(after: i)
      } else if pattern[i] == "." {
        result += "\\."
        i = pattern.index(after: i)
      } else {
        result.append(pattern[i])
        i = pattern.index(after: i)
      }
    }
    result += "$"
    return result
  }
}
