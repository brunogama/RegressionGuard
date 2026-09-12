import Foundation

/// Reads the functions a Swift file declares and decides whether each one still runs as a test.
///
/// Kept apart from `DisabledOrSkippedTestRule` because it answers a question of its own - what
/// this file's test functions are - and because the rule is at its file-length budget. Line
/// based, like the rest of the source-text detection, until the rules move onto parsed syntax.
enum TestFunctionIdentity {
  /// One declared function and whether it reads as a test.
  typealias Function = (name: String, isTest: Bool)

  /// Compares the functions two versions of one file declare.
  ///
  /// - Returns: a finding for every base test function that is gone from head, or that survives
  ///   with its test identity lost.
  static func violations(
    old: String,
    new: String,
    path: String,
    severity: Severity
  ) -> [Violation] {
    // Overloads share a name, so a name maps to a whole overload set rather than one function.
    // The set keeps its test identity as long as any member of it still reads as a test.
    let survivesAsTest = Dictionary(
      functions(in: new).map { ($0.name, $0.isTest) },
      uniquingKeysWith: { $0 || $1 }
    )
    var violations: [Violation] = []

    for function in functions(in: old) where function.isTest {
      guard let isStillTest = survivesAsTest[function.name] else {
        violations.append(removedViolation(function, path, severity))
        continue
      }
      if !isStillTest {
        violations.append(lostIdentityViolation(function, path, severity))
      }
    }
    return violations
  }

  static func functions(in content: String) -> [Function] {
    let lines = content.components(separatedBy: "\n")
    var results: [Function] = []

    for (index, line) in lines.enumerated() {
      guard let name = name(in: line) else { continue }
      results.append((name, isTest: isTest(name: name, near: index, in: lines)))
    }
    return results
  }

  private static func removedViolation(
    _ function: Function,
    _ path: String,
    _ severity: Severity
  ) -> Violation {
    Violation(
      ruleID: DisabledOrSkippedTestRule.ruleID,
      severity: severity,
      file: path,
      message: "Test function `\(function.name)` was removed rather than fixed.",
      detail: nil
    )
  }

  private static func lostIdentityViolation(
    _ function: Function,
    _ path: String,
    _ severity: Severity
  ) -> Violation {
    Violation(
      ruleID: DisabledOrSkippedTestRule.ruleID,
      severity: severity,
      file: path,
      message: "Test function `\(function.name)` lost its test identity.",
      detail: "A removed `test...` name or `@Test` attribute can hide a failing test."
    )
  }

  private static func isTest(name: String, near index: Int, in lines: [String]) -> Bool {
    name.lowercased().hasPrefix("test") || hasTestAttribute(near: index, in: lines)
  }

  private static func hasTestAttribute(near index: Int, in lines: [String]) -> Bool {
    var lookback = index - 1
    var scanned = 0
    while lookback >= 0, scanned < 5 {
      let previous = lines[lookback].trimmingCharacters(in: .whitespaces)
      if previous.isEmpty {
        lookback -= 1
        scanned += 1
        continue
      }
      if previous.contains("@Test") { return true }
      if previous.hasPrefix("func ") || previous.hasSuffix("{") || previous.hasSuffix("}") {
        return false
      }
      lookback -= 1
      scanned += 1
    }
    return false
  }

  /// The identifier a `func` declaration on this line introduces, if any.
  static func name(in line: String) -> String? {
    guard let range = line.range(of: "func ") else { return nil }
    let after = line[range.upperBound...]
    let name = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
    return name.isEmpty ? nil : String(name)
  }
}
