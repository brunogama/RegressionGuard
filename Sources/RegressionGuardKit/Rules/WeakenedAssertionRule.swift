import Foundation

/// Flags assertions that were removed or turned into tautologies instead of genuinely fixed.
///
/// Every one of this rule's detections reads source structure, so all three move to the tree and
/// this file is what remains as the degradation path. See `WeakenedAssertionRule+Syntax.swift` for
/// the syntactic contract and what it catches that these matchers do not.
public struct WeakenedAssertionRule: SyntaxAwareRule {
  public static let ruleID = "weakened_assertion"
  public static let defaultSeverity = Severity.error

  private static let assertionPrefixes: [String] = [
    "XCTAssert", "XCTFail", "XCTUnwrap",
    "#expect", "#require",
  ]

  private static let tautologies: [String] = [
    "XCTAssertTrue(true)",
    "XCTAssertFalse(false)",
    "#expect(true)",
    "XCTAssertEqual(1, 1)",
    "XCTAssertNil(nil)",
  ]

  public init() {}

  /// Nothing here is answered by the diff alone: a weakened assertion is a statement about the
  /// assertions a file makes, which is what the tree reports and what these matchers approximate.
  public func diffViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] { [] }

  public func textFallbackViolations(
    fileDiff: FileDiff,
    context: RuleContext
  ) async -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    let severity = Self.settings(from: context).severity
    let deleted = await deletedFileViolations(
      fileDiff: fileDiff,
      context: context,
      severity: severity
    )
    return tautologyViolations(fileDiff: fileDiff, severity: severity)
      + removedAssertionViolations(fileDiff: fileDiff, severity: severity)
      + deleted
  }

  private func tautologyViolations(fileDiff: FileDiff, severity: Severity) -> [Violation] {
    var violations: [Violation] = []
    for added in fileDiff.addedLines where Self.containsTautology(added.text) {
      let trimmed = added.text.trimmingCharacters(in: .whitespaces)
      violations.append(
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: fileDiff.displayPath,
          line: added.number,
          message: "Assertion replaced with a condition that can never fail.",
          detail: trimmed
        )
      )
    }
    return violations
  }

  private func removedAssertionViolations(
    fileDiff: FileDiff,
    severity: Severity
  ) -> [Violation] {
    let removedAssertions = assertions(in: fileDiff.removedLines)
    let addedAssertions = assertions(in: fileDiff.addedLines)
    guard removedAssertions.count > addedAssertions.count, !fileDiff.isDeleted else {
      return []
    }

    let delta = removedAssertions.count - addedAssertions.count
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: fileDiff.displayPath,
        line: removedAssertions.first?.number,
        message: "\(delta) assertion(s) removed without replacement.",
        detail: Self.detail(for: removedAssertions)
      )
    ]
  }

  private func deletedFileViolations(
    fileDiff: FileDiff,
    context: RuleContext,
    severity: Severity
  ) async -> [Violation] {
    guard fileDiff.isDeleted, let oldPath = fileDiff.oldPath else { return [] }
    guard let oldContent = await context.repository.show(ref: context.baseRef, path: oldPath)
    else {
      return []
    }

    let count = Self.assertionCount(in: oldContent)
    guard count > 0 else { return [] }
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: oldPath,
        message: "Deleted test file contained \(count) assertion(s).",
        detail: "Those assertions are no longer checked anywhere."
      )
    ]
  }

  private func assertions(in lines: [DiffLine]) -> [DiffLine] {
    lines.filter { line in Self.containsAssertion(line.text) }
  }

  private static func containsAssertion(_ text: String) -> Bool {
    assertionPrefixes.contains { text.contains($0) }
  }

  private static func containsTautology(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return tautologies.contains { trimmed.contains($0) }
  }

  private static func assertionCount(in content: String) -> Int {
    assertionPrefixes.reduce(0) { total, prefix in
      total + content.components(separatedBy: prefix).count - 1
    }
  }

  private static func detail(for assertions: [DiffLine]) -> String {
    assertions
      .map { $0.text.trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
  }
}
