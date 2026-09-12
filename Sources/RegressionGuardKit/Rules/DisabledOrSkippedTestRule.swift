import Foundation

/// Flags changes that make a test stop running without actually fixing it.
public struct DisabledOrSkippedTestRule: Rule {
  public static let ruleID = "disabled_or_skipped_test"
  public static let defaultSeverity = Severity.error

  private static let skipMarkers: [String] = [
    "XCTSkip",
    ".disabled(",
    ".disabled)",
    "@Disabled",
    "throw XCTSkip",
  ]

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    let severity = Self.settings(from: context).severity
    return deletedTestFileViolations(fileDiff: fileDiff, severity: severity)
      + skipMarkerViolations(fileDiff: fileDiff, severity: severity)
      + commentedOutTestViolations(fileDiff: fileDiff, severity: severity)
      + functionIdentityViolations(fileDiff: fileDiff, context: context, severity: severity)
  }

  private func deletedTestFileViolations(
    fileDiff: FileDiff,
    severity: Severity
  ) -> [Violation] {
    guard fileDiff.isDeleted, let oldPath = fileDiff.oldPath else { return [] }
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: oldPath,
        message: "Test file was deleted instead of fixed: \(oldPath)",
        detail: "Use the approval marker if this test file is genuinely obsolete."
      )
    ]
  }

  private func skipMarkerViolations(fileDiff: FileDiff, severity: Severity) -> [Violation] {
    var violations: [Violation] = []
    for added in fileDiff.addedLines where Self.containsSkipMarker(added.text) {
      violations.append(
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: fileDiff.displayPath,
          line: added.number,
          message: "Test appears to be disabled or skipped instead of fixed.",
          detail: added.text.trimmingCharacters(in: .whitespaces)
        )
      )
    }
    return violations
  }

  private func commentedOutTestViolations(
    fileDiff: FileDiff,
    severity: Severity
  ) -> [Violation] {
    let removedTexts = Set(fileDiff.removedLines.map { Self.normalizedCode($0.text) })
    var violations: [Violation] = []

    for added in fileDiff.addedLines {
      let trimmed = added.text.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("//") else { continue }
      let uncommented = String(trimmed.dropFirst(2))
        .trimmingCharacters(in: .whitespaces)
      if !uncommented.isEmpty, removedTexts.contains(Self.normalizedCode(uncommented)) {
        violations.append(commentedOutViolation(added, uncommented, fileDiff, severity))
      }
    }

    return violations
  }

  private func functionIdentityViolations(
    fileDiff: FileDiff,
    context: RuleContext,
    severity: Severity
  ) -> [Violation] {
    guard let oldPath = fileDiff.oldPath else { return [] }
    let newPath = fileDiff.newPath ?? oldPath
    guard let oldContent = context.repository.show(ref: context.baseRef, path: oldPath) else {
      return []
    }
    guard let newContent = context.repository.show(ref: context.headRef, path: newPath) else {
      return []
    }
    return Self.compareTestFunctions(
      old: oldContent,
      new: newContent,
      path: fileDiff.displayPath,
      severity: severity
    )
  }

  private func commentedOutViolation(
    _ added: DiffLine,
    _ uncommented: String,
    _ fileDiff: FileDiff,
    _ severity: Severity
  ) -> Violation {
    Violation(
      ruleID: Self.ruleID,
      severity: severity,
      file: fileDiff.displayPath,
      line: added.number,
      message: "Test code appears to have been commented out rather than fixed.",
      detail: uncommented
    )
  }

  private static func containsSkipMarker(_ text: String) -> Bool {
    skipMarkers.contains { text.contains($0) }
  }

  private static func normalizedCode(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespaces)
  }

  private typealias TestFunction = (name: String, isTest: Bool)

  private static func compareTestFunctions(
    old: String,
    new: String,
    path: String,
    severity: Severity
  ) -> [Violation] {
    // Overloads share a name, so a name maps to a whole overload set rather than one function.
    // The set keeps its test identity as long as any member of it still reads as a test.
    let survivesAsTest = Dictionary(
      extractFunctions(from: new).map { ($0.name, $0.isTest) },
      uniquingKeysWith: { $0 || $1 }
    )
    var violations: [Violation] = []

    for oldFunc in extractFunctions(from: old) where oldFunc.isTest {
      guard let isStillTest = survivesAsTest[oldFunc.name] else {
        violations.append(removedFunctionViolation(oldFunc, path, severity))
        continue
      }
      if !isStillTest {
        violations.append(lostIdentityViolation(oldFunc, path, severity))
      }
    }
    return violations
  }

  private static func removedFunctionViolation(
    _ function: TestFunction,
    _ path: String,
    _ severity: Severity
  ) -> Violation {
    Violation(
      ruleID: ruleID,
      severity: severity,
      file: path,
      message: "Test function `\(function.name)` was removed rather than fixed.",
      detail: nil
    )
  }

  private static func lostIdentityViolation(
    _ function: TestFunction,
    _ path: String,
    _ severity: Severity
  ) -> Violation {
    Violation(
      ruleID: ruleID,
      severity: severity,
      file: path,
      message: "Test function `\(function.name)` lost its test identity.",
      detail: "A removed `test...` name or `@Test` attribute can hide a failing test."
    )
  }

  private static func extractFunctions(from content: String) -> [TestFunction] {
    let lines = content.components(separatedBy: "\n")
    var results: [TestFunction] = []

    for (index, line) in lines.enumerated() {
      guard let name = functionName(in: line) else { continue }
      let function: TestFunction = (
        name, isTest: isTest(name: name, near: index, in: lines)
      )
      results.append(function)
    }
    return results
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

  private static func functionName(in line: String) -> String? {
    guard let range = line.range(of: "func ") else { return nil }
    let after = line[range.upperBound...]
    let name = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
    return name.isEmpty ? nil : String(name)
  }
}
