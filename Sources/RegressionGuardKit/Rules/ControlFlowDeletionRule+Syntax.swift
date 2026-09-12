import Foundation

/// The syntactic contract for `behavior_deletion`.
///
/// The whole rule moves to the tree. "Control-flow line(s) removed" becomes "branches the file no
/// longer has", counted as nodes on each side:
///
/// - One `if` written over four lines counts once, not four times, so reformatting a condition no
///   longer looks like three deletions.
/// - A `return` inside a string literal, a comment mentioning `guard `, and a variable called
///   `catchphrase` stop counting at all - the keyword list matched all three.
/// - The `added.isEmpty` guard, which a single unrelated added `return` was enough to defeat,
///   becomes the difference between the two counts, so replacing five branches with one is still
///   a net removal of four.
///
/// The count is over the whole file rather than the changed lines, because a branch that was
/// deleted is by definition not in the head file to be counted there. The diff still has the final
/// say on whether anything was removed at all, and on where the finding is reported.
///
/// Reported severity and rule ID are unchanged: this is a precision upgrade, not a new family.
public extension ControlFlowDeletionRule {
  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.isProductionPath(fileDiff), let base = syntax.baseTree else {
      return []
    }
    let map = fileDiff.changedLineMap
    guard !map.removedLines.isEmpty else { return [] }

    let removed = ControlFlowNode.nodes(in: base)
    let surviving = syntax.headTree.map { ControlFlowNode.nodes(in: $0).count } ?? 0
    let delta = removed.count - surviving
    guard delta >= Self.removalThreshold else { return [] }

    // Only branches the change actually removed. A branch the diff never names cannot be what the
    // count is talking about, and reporting one would put the finding on code the author never
    // touched - which is the failure the whole line mapping exists to prevent. A deleted file has
    // no head side for the line to land on, and `nil` is the honest answer there.
    let deleted = removed.filter { map.touches($0.span, at: .base) }
    guard let anchor = deleted.first else { return [] }

    return [
      Violation(
        ruleID: Self.ruleID,
        severity: Self.settings(from: context).severity,
        file: fileDiff.displayPath,
        line: map.reportLine(for: anchor.span, at: .base),
        message: fileDiff.isDeleted
          ? "Deleted production file carried \(removed.count) control-flow branch(es)."
          : "\(delta) control-flow branch(es) removed without replacement.",
        detail: Self.detail(for: deleted)
      )
    ]
  }

  private static func detail(for nodes: [SyntaxNode]) -> String {
    nodes.prefix(5).map { ControlFlowNode.description(of: $0) }.joined(separator: "\n")
  }
}
