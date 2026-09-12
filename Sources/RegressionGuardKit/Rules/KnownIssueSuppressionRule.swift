import Foundation

/// Flags a test whose failure the change wrapped in `withKnownIssue`.
///
/// Distinct from `disabled_or_skipped_test` rather than a marker inside it. A skipped test does
/// not run; a known-issue suppression runs the test, runs its assertions, and absorbs the
/// resulting failure as expected. The remediation differs too: a skip is fixed by restoring
/// execution, a suppression by fixing the issue or justifying it with a tracking reference.
///
/// Advisory by default, and that is the substantive reason for the separate rule ID. Folding it
/// into `disabled_or_skipped_test` would hand it that family's blocking severity on day one, and
/// suppressing a genuinely known upstream failure is ordinary, reviewable practice. It ships
/// advisory and earns promotion through the existing calibration path, if the evidence supports
/// one.
///
/// AST-only: there is no text fallback, because matching `withKnownIssue` against added lines
/// would fire on the string in this very doc comment. A run without a parser reports the missing
/// evidence as a gap instead.
public struct KnownIssueSuppressionRule: SyntaxAwareRule {
  public static let ruleID = "known_issue_suppression"
  public static let defaultSeverity = Severity.warning

  /// Calls that absorb a test's failure rather than letting it be reported.
  ///
  /// Matched exactly, not by prefix: `withKnownIssueTracker` is somebody's helper, not this.
  private static let suppressingCalls: Set<String> = ["withKnownIssue"]

  public init() {}

  public func syntacticEvidenceRequests(for fileDiff: FileDiff) -> [SyntacticEvidenceRequest] {
    guard fileDiff.isSwiftSource else { return [] }
    return [SyntacticEvidenceRequest(fileDiff: fileDiff)]
  }

  public func diffViolations(fileDiff: FileDiff, context: RuleContext) async -> [Violation] {
    []
  }

  public func textFallbackViolations(
    fileDiff: FileDiff,
    context: RuleContext
  ) async -> [Violation] {
    []
  }

  public func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    guard let head = syntax.headTree else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap

    return Self.suppressions(in: head)
      // The call's own lines, not its whole span: a suppression wraps its test in a trailing
      // closure, so the span covers the body. Editing an assertion under a suppression that was
      // already there is not this change's doing.
      .filter { map.changeScope(of: $0, at: .head) == .own }
      .map { call in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: syntax.path,
          line: map.reportLine(for: call.span, at: .head),
          message: "Test failure is suppressed as a known issue instead of fixed.",
          detail: Self.detail(for: call, in: head)
        )
      }
  }

  private static func suppressions(in tree: SyntaxTree) -> [SyntaxNode] {
    tree.nodes(ofAnyKind: [.functionCallExpr, .macroExpansionExpr]).filter { node in
      node.name.map(suppressingCalls.contains) ?? false
    }
  }

  private static func detail(for call: SyntaxNode, in tree: SyntaxTree) -> String {
    guard
      let name = tree.innermostNode(ofKind: .functionDecl, containing: call.span)?.name
    else {
      return "`withKnownIssue` absorbs the failure this test would otherwise report."
    }
    return "`withKnownIssue` absorbs the failure `" + name + "` would otherwise report."
  }
}
