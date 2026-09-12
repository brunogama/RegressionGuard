import Foundation
import Testing
@testable import RegressionGuardKit

/// A rule that reports which of its three detection groups ran, so the dispatch contract can be
/// checked without a real detector's opinions getting in the way.
private struct ProbeRule: SyntaxAwareRule {
  static let ruleID = "probe"
  static let defaultSeverity = Severity.warning

  func diffViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    [Self.finding("diff", fileDiff)]
  }

  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    [Self.finding("syntactic", fileDiff)]
  }

  func textFallbackViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    [Self.finding("textFallback", fileDiff)]
  }

  private static func finding(_ group: String, _ fileDiff: FileDiff) -> Violation {
    Violation(ruleID: ruleID, severity: .warning, file: fileDiff.displayPath, message: group)
  }
}

@Suite("Syntax-aware rule dispatch tests")
struct SyntaxAwareRuleTests {
  fileprivate let rule = ProbeRule()
  let path = "Sources/Thing.swift"

  @Test("declaring the protocol declares the need for parsed evidence")
  func declaresTheNeed() {
    #expect(ProbeRule.requiresSyntacticEvidence)
  }

  @Test("a caller holding only a diff gets the whole line-based path")
  func fileDiffEntryPointIsTheWholeTextPath() async {
    let violations = await rule.evaluate(
      fileDiff: TestSupport.fileDiff(path: path, added: ["x"]),
      context: TestSupport.context()
    )

    #expect(violations.map(\.message) == ["diff", "textFallback"])
    #expect(violations.allSatisfy { $0.evidence == .diff })
  }

  @Test("parsed trees replace the text fallback and keep the diff detections")
  func parsedTreesReplaceTheFallback() async {
    let violations = await evaluate(syntax: parsedEvidence)

    #expect(violations.map(\.message) == ["diff", "syntactic"])
    #expect(violations.first { $0.message == "syntactic" }?.evidence == .syntax)
    #expect(violations.first { $0.message == "diff" }?.evidence == .diff)
  }

  @Test("a gap on either side falls back to the text path and marks it degraded")
  func aGapDegradesToTheTextPath() async {
    let violations = await evaluate(syntax: SyntaxFixture.degradedEvidence(path: path))

    #expect(violations.map(\.message) == ["diff", "textFallback"])
    #expect(violations.first { $0.message == "textFallback" }?.evidence == .degradedDiff)
  }

  @Test("an absent side is not a gap, because nothing is missing")
  func anAbsentSideIsNotAGap() async {
    let syntax = SyntacticFileEvidence(
      path: path,
      base: .absent(.fileAdded),
      head: .parsed(SyntaxFixture.tree(path: path, ref: .head, []))
    )
    let violations = await evaluate(syntax: syntax)

    #expect(violations.map(\.message) == ["diff", "syntactic"])
  }

  @Test("a file no rule asked about is not degraded, it was never expected to be parsed")
  func anUnrequestedFileIsNotDegraded() async {
    let violations = await evaluate(syntax: nil)

    #expect(violations.map(\.message) == ["diff", "textFallback"])
    #expect(violations.allSatisfy { $0.evidence == .diff })
  }

  private var parsedEvidence: SyntacticFileEvidence {
    SyntaxFixture.evidence(
      path: path,
      base: SyntaxFixture.tree(path: path, ref: .base, []),
      head: SyntaxFixture.tree(path: path, ref: .head, [])
    )
  }

  private func evaluate(syntax: SyntacticFileEvidence?) async -> [Violation] {
    let context = TestSupport.context()
    return await rule.evaluate(
      evidence: SyntaxFixture.bundle(
        fileDiff: TestSupport.fileDiff(path: path, added: ["x"]),
        syntax: syntax,
        context: context
      ),
      context: context
    )
  }
}
