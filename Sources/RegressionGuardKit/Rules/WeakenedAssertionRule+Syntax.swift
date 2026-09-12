import Foundation

/// The syntactic contract for `weakened_assertion`.
///
/// All three of the rule's detections move to the tree, because all three ask a question about the
/// assertions a file makes and the line path can only ask about the text of the lines that
/// changed:
///
/// - A tautology stops being a list of exact spellings and becomes a property of the call's
///   arguments, so `XCTAssertTrue( true )`, `#expect(1 == 1)` and `XCTAssertEqual(2, 2)` - all of
///   which pass today - are caught, while `XCTAssertEqual(sut.total, 42)` stays healthy.
/// - A net removal counts assertion *calls* on each side of the whole file rather than lines
///   containing an assertion prefix, so a multi-line assertion counts once and an assertion moved
///   between two functions is not reported as deleted.
/// - A deleted test file's assertions are counted off its base tree rather than by splitting its
///   source on prefix strings, which also drops a per-file `git show` the batched provider has
///   already paid for.
///
/// Reported severity and rule ID are unchanged: this is a precision upgrade, not a new family.
public extension WeakenedAssertionRule {
  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap
    return tautologyViolations(syntax: syntax, map: map, severity: severity)
      + removedAssertionViolations(fileDiff: fileDiff, syntax: syntax, map: map, severity: severity)
  }

  /// Assertions the change introduced or rewrote that can no longer fail.
  ///
  /// Scoped to the calls the change actually touched. A tautology that was already in the file is
  /// not this change's doing, and reporting it would put a finding on code the author never wrote.
  private func tautologyViolations(
    syntax: SyntacticFileEvidence,
    map: ChangedLineMap,
    severity: Severity
  ) -> [Violation] {
    guard let head = syntax.headTree else { return [] }
    return AssertionCall.calls(in: head)
      .filter { AssertionCall.cannotFail($0) && map.touches($0.span, at: .head) }
      .map { call in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: syntax.path,
          line: map.reportLine(for: call.span, at: .head),
          message: "Assertion replaced with a condition that can never fail.",
          detail: (AssertionCall.calleeName(of: call) ?? "The assertion")
            + " is given only constants, so its result cannot depend on the code under test."
        )
      }
  }

  /// Assertions that are in the base file and gone from head, counted as calls.
  ///
  /// A deleted file is the same question with no head side at all, so it is the same count against
  /// zero - and the honest report line for a file a reader cannot open is none.
  private func removedAssertionViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    map: ChangedLineMap,
    severity: Severity
  ) -> [Violation] {
    guard let base = syntax.baseTree else { return [] }
    let removed = AssertionCall.calls(in: base)
    let surviving = syntax.headTree.map { AssertionCall.calls(in: $0).count } ?? 0
    let delta = removed.count - surviving
    guard delta > 0 else { return [] }

    // The first assertion the change actually removed, and no fallback to one it did not: a line
    // pointing at an assertion the author never touched is worse than no line at all, and
    // `Violation.line` is optional for exactly this. A deleted file has no head side to land on
    // and reports none, which is the same answer by a different route.
    let anchor = removed.first { map.touches($0.span, at: .base) }
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: fileDiff.isDeleted ? (fileDiff.oldPath ?? syntax.path) : syntax.path,
        line: anchor.flatMap { map.reportLine(for: $0.span, at: .base) },
        message: fileDiff.isDeleted
          ? "Deleted test file contained \(removed.count) assertion(s)."
          : "\(delta) assertion(s) removed without replacement.",
        detail: fileDiff.isDeleted
          ? "Those assertions are no longer checked anywhere."
          : "The file asserted \(removed.count) time(s) at base and \(surviving) now."
      )
    ]
  }
}
