import Foundation

/// The syntactic contract for `error_handling_collapse`.
///
/// Both detections move to the tree:
///
/// - A force-unwrap becomes a `forceUnwrapExpr` the change touched, instead of a regular
///   expression over a line's characters. The regex already carries three carve-outs for `!=`, a
///   leading `!`, and an implicitly-unwrapped type annotation, and still matches a `!` inside a
///   string literal or a comment. A node is a force-unwrap or it is not.
/// - A swallowed `catch` becomes a `catchClause` whose body holds nothing, so a catch that spans
///   several lines, or that holds only a comment excusing itself, is caught - and the finding
///   carries the line, which the text path has no way to produce because it matches across the
///   added lines joined together.
///
/// The force-unwrap family named as an AST-only candidate elsewhere lands here rather than under a
/// new rule ID: `error_handling_collapse` already owns it, so sharpening it is a precision upgrade
/// and keeps the rule ID and severity a guarded repository already configured.
public extension UncheckedErrorPathRule {
  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.isProductionPath(fileDiff), let head = syntax.headTree else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap
    return forceUnwrapViolations(
      in: head,
      map: map,
      path: fileDiff.displayPath,
      severity: severity
    )
      + swallowedCatchViolations(
        in: head,
        map: map,
        path: fileDiff.displayPath,
        severity: severity
      )
  }

  private func forceUnwrapViolations(
    in head: SyntaxTree,
    map: ChangedLineMap,
    path: String,
    severity: Severity
  ) -> [Violation] {
    head.nodes(ofKind: .forceUnwrapExpr)
      .filter { map.touches($0.span, at: .head) }
      .map { node in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: path,
          line: map.reportLine(for: node.span, at: .head),
          message: "Force-unwrap introduced instead of proper error/optional handling.",
          detail: node.name.map { "`" + $0 + "` is force-unwrapped." }
        )
      }
  }

  /// A `catch` whose body holds no statements.
  ///
  /// A body projected with no `codeBlock` at all is left alone rather than assumed empty: an
  /// unrecognised projection is not evidence that the error is discarded.
  private func swallowedCatchViolations(
    in head: SyntaxTree,
    map: ChangedLineMap,
    path: String,
    severity: Severity
  ) -> [Violation] {
    head.nodes(ofKind: .catchClause)
      .filter { map.touches($0.span, at: .head) && Self.swallowsTheError($0) }
      .map { node in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: path,
          line: map.reportLine(for: node.span, at: .head),
          message: "Empty `catch` block introduced - the error is now silently discarded.",
          detail: nil
        )
      }
  }

  private static func swallowsTheError(_ node: SyntaxNode) -> Bool {
    guard let body = node.firstNode(ofKind: .codeBlock) else { return false }
    return body.children.isEmpty
  }
}
