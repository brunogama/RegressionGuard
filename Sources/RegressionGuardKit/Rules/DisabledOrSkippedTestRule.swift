import Foundation

/// Flags changes that make a test stop running without actually fixing it.
///
/// Two of this rule's four detections move to the tree - the skip markers and the test-function
/// identity check - and two stay where they are. A deleted test file is a fact about the diff, and
/// a test commented out in place is a comparison between an added comment and the removed line it
/// repeats: both are answered by the diff itself whether or not a parser ran, so both are
/// `diffViolations` rather than a fallback. See `DisabledOrSkippedTestRule+Syntax.swift`.
public struct DisabledOrSkippedTestRule: SyntaxAwareRule {
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

  public func diffViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    let severity = Self.settings(from: context).severity
    return deletedTestFileViolations(fileDiff: fileDiff, severity: severity)
      + commentedOutTestViolations(fileDiff: fileDiff, severity: severity)
  }

  public func textFallbackViolations(
    fileDiff: FileDiff,
    context: RuleContext
  ) async -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    let severity = Self.settings(from: context).severity
    let identity = await functionIdentityViolations(
      fileDiff: fileDiff,
      context: context,
      severity: severity
    )
    return skipMarkerViolations(fileDiff: fileDiff, severity: severity) + identity
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
    for added in fileDiff.addedLines
    where Self.containsSkipMarker(Self.ignoringDeclaredName(added.text)) {
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
  ) async -> [Violation] {
    guard let oldPath = fileDiff.oldPath else { return [] }
    let newPath = fileDiff.newPath ?? oldPath
    guard let oldContent = await context.repository.show(ref: context.baseRef, path: oldPath)
    else {
      return []
    }
    guard let newContent = await context.repository.show(ref: context.headRef, path: newPath)
    else {
      return []
    }
    return TestFunctionIdentity.violations(
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

  /// The line with the identifier a `func` declares removed, and nothing else.
  ///
  /// A test named after what it checks - `testFlagsXCTSkipAddedToATest` - is not a skipped test,
  /// and matching the marker inside its own name blocks the author for naming the thing. Only the
  /// identifier goes: the rest of the line stays, so a one-liner that really does
  /// `func f() { throw XCTSkip(...) }` is still caught.
  private static func ignoringDeclaredName(_ text: String) -> String {
    guard let keyword = text.range(of: "func "),
      let name = TestFunctionIdentity.name(in: text),
      let nameEnd = text.index(keyword.upperBound, offsetBy: name.count, limitedBy: text.endIndex)
    else { return text }
    return text.replacingCharacters(in: keyword.upperBound..<nameEnd, with: "")
  }

  private static func normalizedCode(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespaces)
  }
}
