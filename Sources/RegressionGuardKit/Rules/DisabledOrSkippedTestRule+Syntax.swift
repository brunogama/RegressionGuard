import Foundation

/// The syntactic contract for `disabled_or_skipped_test`.
///
/// Two detections move here:
///
/// - Skip markers become marker *nodes* the change touched, rather than added lines containing a
///   marker substring. That names the declaration that stopped running, catches a trait written
///   across several lines, sees a whole `@Suite(.disabled)` the line path has no concept of, and
///   stops matching markers written inside comments, string payloads, or a test's own name - the
///   last of which the line path has to work around by editing the declared name out of the line
///   before matching it.
/// - Test-function identity compares the `functionDecl` nodes of the base and head trees instead
///   of scanning for `func ` and guessing at a nearby `@Test` within five lines. It also drops the
///   rule's two per-file `git show` calls, since both trees arrive from the batched provider.
///
/// Reported severity and rule ID are unchanged: this is a precision upgrade, not a new family.
public extension DisabledOrSkippedTestRule {
  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap
    return skipMarkerViolations(syntax: syntax, map: map, severity: severity)
      + TestFunctionIdentity.violations(syntax: syntax, map: map, severity: severity)
  }

  /// Markers the change put there.
  ///
  /// Scoped to the marker's own span, not to the declaration around it: a test that was already
  /// disabled before this change stays out of the report even when its body was edited, which is
  /// the behaviour the line path gets for free by only ever seeing added lines.
  private func skipMarkerViolations(
    syntax: SyntacticFileEvidence,
    map: ChangedLineMap,
    severity: Severity
  ) -> [Violation] {
    guard let head = syntax.headTree else { return [] }
    return TestSkipMarker.markers(in: head)
      .filter { map.touches($0.span, at: .head) }
      .map { marker in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: syntax.path,
          line: map.reportLine(for: marker.span, at: .head),
          message: "Test appears to be disabled or skipped instead of fixed.",
          detail: Self.detail(for: marker, in: head)
        )
      }
  }

  private static func detail(for marker: SyntaxNode, in tree: SyntaxTree) -> String {
    let marked = TestSkipMarker.description(of: marker)
    guard
      let declaration = tree.innermostNode(ofKind: .functionDecl, containing: marker.span)
        ?? tree.innermostNode(ofKind: .classDecl, containing: marker.span)
        ?? tree.innermostNode(ofKind: .structDecl, containing: marker.span),
      let name = declaration.name
    else {
      return marked + " stops a test from running."
    }
    return marked + " stops `" + name + "` from running."
  }
}
