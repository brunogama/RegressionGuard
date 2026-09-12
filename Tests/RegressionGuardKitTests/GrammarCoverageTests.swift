import Foundation
import Testing

@testable import RegressionGuardKit

/// A parser older than the source it reads cannot represent the newer syntax.
///
/// The rules written to catch a construct simply stop seeing it. Where the parser knows it
/// failed, that has to surface as an inconclusive result rather than a pass.
@Suite("Grammar coverage tests")
struct GrammarCoverageTests {
  private static let path = "Sources/A.swift"

  /// A node carrying syntax the grammar could not represent, such as `nonisolated(nonsending)`
  /// read by a 600-series parser.
  private static func unrepresentable(lines: ClosedRange<Int>) -> SyntaxNode {
    SyntaxNode(
      kind: .functionDecl,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: "handoff",
      hasError: true
    )
  }

  private static func clean(lines: ClosedRange<Int>) -> SyntaxNode {
    SyntaxNode(
      kind: .functionDecl,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: "example"
    )
  }

  /// A change touching exactly `line` on the head side.
  private static func diff(addedLine line: Int) -> FileDiff {
    FileDiff(
      oldPath: path,
      newPath: path,
      isDeleted: false,
      isAdded: false,
      isRenamed: false,
      hunks: [
        Hunk(
          oldStart: line,
          newStart: line,
          lines: [DiffLine(kind: .added, number: line, text: "touched")]
        )
      ]
    )
  }

  private static func evidence() -> SyntacticFileEvidence {
    SyntaxFixture.evidence(
      path: path,
      base: SyntaxFixture.tree(path: path, ref: .base, [clean(lines: 4...6)]),
      head: SyntaxFixture.tree(
        path: path,
        ref: .head,
        [clean(lines: 4...6), unrepresentable(lines: 10...12)]
      )
    )
  }

  @Test("a node reports only its own unrepresentable syntax, not a descendant's")
  func errorIsNodeLocal() {
    let parent = SyntaxNode(
      kind: .structDecl,
      span: LineSpan(start: 1, end: 20),
      name: "MySuite",
      children: [Self.unrepresentable(lines: 10...12)]
    )
    #expect(!parent.hasError)
    #expect(parent.hasErrorInSubtree)
    #expect(parent.children[0].hasError)
  }

  @Test("a tree finds the unrepresentable nodes on given lines")
  func errorNodesOnLines() {
    let tree = SyntaxFixture.tree(
      path: Self.path,
      ref: .head,
      [Self.clean(lines: 4...6), Self.unrepresentable(lines: 10...12)]
    )
    #expect(tree.errorNodes(touching: [11]).map(\.name) == ["handoff"])
    #expect(tree.errorNodes(touching: [5]).isEmpty)
    #expect(tree.errorNodes(touching: []).isEmpty)
  }

  @Test("a change that touches unrepresentable syntax becomes a reported gap")
  func changedRegionWithErrorIsAGap() {
    let gaps = Self.evidence().grammarGaps(in: Self.diff(addedLine: 11).changedLineMap)
    #expect(gaps.count == 1)
    #expect(gaps.first?.ref == .head)
    #expect(gaps.first?.reason == .grammarUnrepresentable)
    #expect(gaps.first?.path == Self.path)
  }

  @Test("unrepresentable syntax the change never touched is not a gap")
  func untouchedErrorIsNotAGap() {
    #expect(Self.evidence().grammarGaps(in: Self.diff(addedLine: 5).changedLineMap).isEmpty)
  }

  @Test("a side with no tree contributes no grammar gap, because it already reports one")
  func gapSideIsNotDoubleReported() {
    let evidence = SyntaxFixture.degradedEvidence(path: Self.path)
    #expect(evidence.grammarGaps(in: Self.diff(addedLine: 11).changedLineMap).isEmpty)
  }

  @Test("a tree that localises no error still yields a gap when it reports one file-wide")
  func fileLevelErrorWithoutNodeIsStillAGap() {
    let tree = SyntaxTree(
      path: Self.path,
      ref: SyntaxRef.head.rawValue,
      root: SyntaxNode(kind: .sourceFile, span: LineSpan(start: 1, end: 100)),
      lineCount: 100,
      hasParseErrors: true
    )
    let evidence = SyntacticFileEvidence(
      path: Self.path,
      base: .parsed(SyntaxFixture.tree(path: Self.path, ref: .base, [Self.clean(lines: 4...6)])),
      head: .parsed(tree)
    )

    let gaps = evidence.grammarGaps(in: Self.diff(addedLine: 11).changedLineMap)
    #expect(gaps.map(\.reason) == [.grammarUnrepresentable])
    #expect(gaps.first?.ref == .head)
  }

  @Test("a clean tree on an untouched side yields nothing")
  func cleanTreeYieldsNothing() {
    let evidence = SyntaxFixture.evidence(
      path: Self.path,
      base: SyntaxFixture.tree(path: Self.path, ref: .base, [Self.clean(lines: 4...6)]),
      head: SyntaxFixture.tree(path: Self.path, ref: .head, [Self.clean(lines: 4...6)])
    )
    #expect(evidence.grammarGaps(in: Self.diff(addedLine: 5).changedLineMap).isEmpty)
  }

  @Test("the engine records the grammar its provider parsed with")
  func engineRecordsProviderGrammar() async {
    let engine = RuleEngine(rules: [], syntacticEvidenceProvider: StubProvider())
    let result = await engine.evaluate(diff: [], context: TestSupport.context())
    #expect(result.syntaxGrammar == SyntaxGrammar(alignmentSeries: 603))
  }

  @Test("a run with no parser records no grammar, rather than implying one")
  func engineWithoutProviderRecordsNoGrammar() async {
    let engine = RuleEngine(rules: [])
    let result = await engine.evaluate(diff: [], context: TestSupport.context())
    #expect(result.syntaxGrammar == nil)
  }

  private struct StubProvider: SyntacticEvidenceProvider {
    var grammar: SyntaxGrammar? { SyntaxGrammar(alignmentSeries: 603) }

    func syntacticEvidence(for requests: [SyntacticEvidenceRequest]) -> SyntacticEvidence {
      SyntacticEvidence(files: [])
    }
  }

  @Test("the engine reports a grammar gap alongside the missing-evidence gaps")
  func engineReportsGrammarGap() async {
    let diff = Self.diff(addedLine: 11)
    let bundle = EvidenceBundle(
      fileDiffs: [diff],
      commit: CommitEvidence(baseRef: "base", headRef: "head", messages: [])
    ).withSyntacticEvidence(SyntacticEvidence(files: [Self.evidence()]))
    let engine = RuleEngine(rules: [])
    let result = await engine.evaluate(evidence: bundle, context: TestSupport.context())
    let reasons: [SyntaxEvidenceGapReason] = result.syntacticEvidenceGaps.map(\.reason)
    #expect(reasons == [.grammarUnrepresentable])
  }
}
