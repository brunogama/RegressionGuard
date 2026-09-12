import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Production shortcut rule syntax tests")
struct ProductionShortcutRuleSyntaxTests {
  let path = "Sources/Validator.swift"

  // MARK: - behavior_deletion

  @Test("flags branches that left the file, counted as nodes")
  func flagsRemovedBranches() async {
    let violations = await evaluate(
      rule: ControlFlowDeletionRule(),
      base: [
        SyntaxFixture.node(.guardStmt, lines: 4...4),
        SyntaxFixture.node(.ifExpr, lines: 5...5),
        SyntaxFixture.node(.throwStmt, lines: 6...6),
      ],
      head: [],
      lines: [
        DiffLine(kind: .removed, number: 4, text: ""),
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .removed, number: 6, text: ""),
      ]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("3 control-flow branch(es)") == true)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("counts one branch spread over several lines once")
  func countsAMultiLineBranchOnce() async {
    let violations = await evaluate(
      rule: ControlFlowDeletionRule(),
      base: [SyntaxFixture.node(.ifExpr, lines: 4...8)],
      head: [SyntaxFixture.node(.ifExpr, lines: 4...5)],
      lines: [
        DiffLine(kind: .removed, number: 4, text: ""),
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .removed, number: 6, text: ""),
        DiffLine(kind: .removed, number: 7, text: ""),
        DiffLine(kind: .removed, number: 8, text: ""),
        DiffLine(kind: .added, number: 4, text: ""),
        DiffLine(kind: .added, number: 5, text: ""),
      ]
    )

    #expect(violations.isEmpty)
  }

  @Test("a single unrelated added branch no longer hides four removals")
  func netRemovalSurvivesAnAddedBranch() async {
    let violations = await evaluate(
      rule: ControlFlowDeletionRule(),
      base: [
        SyntaxFixture.node(.guardStmt, lines: 4...4),
        SyntaxFixture.node(.guardStmt, lines: 5...5),
        SyntaxFixture.node(.guardStmt, lines: 6...6),
        SyntaxFixture.node(.guardStmt, lines: 7...7),
        SyntaxFixture.node(.ifExpr, lines: 8...8),
      ],
      head: [SyntaxFixture.node(.returnStmt, lines: 4...4)],
      lines: [
        DiffLine(kind: .removed, number: 4, text: ""),
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .removed, number: 6, text: ""),
        DiffLine(kind: .removed, number: 7, text: ""),
        DiffLine(kind: .removed, number: 8, text: ""),
        DiffLine(kind: .added, number: 4, text: ""),
      ]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("4 control-flow branch(es)") == true)
  }

  @Test("says nothing when the count dropped but no removed line names a branch")
  func silentWhenNoRemovedBranchIsInTheChange() async {
    // Branches on lines 20-22, a deletion on line 4: the count fell, but not on any evidence this
    // diff carries. Reporting would anchor the finding to code the change never touched.
    let violations = await evaluate(
      rule: ControlFlowDeletionRule(),
      base: [
        SyntaxFixture.node(.guardStmt, lines: 20...20),
        SyntaxFixture.node(.ifExpr, lines: 21...21),
        SyntaxFixture.node(.throwStmt, lines: 22...22),
      ],
      head: [],
      lines: [DiffLine(kind: .removed, number: 4, text: "")]
    )

    #expect(violations.isEmpty)
  }

  @Test("names a deleted production file as deleted rather than as a partial removal")
  func namesADeletedProductionFile() async {
    let context = TestSupport.context()
    let fileDiff = SyntaxFixture.diff(
      path: path,
      lines: [
        DiffLine(kind: .removed, number: 4, text: ""),
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .removed, number: 6, text: ""),
      ],
      isDeleted: true
    )
    let syntax = SyntacticFileEvidence(
      path: path,
      base: .parsed(
        SyntaxFixture.tree(
          path: path,
          ref: .base,
          [
            SyntaxFixture.node(.guardStmt, lines: 4...4),
            SyntaxFixture.node(.ifExpr, lines: 5...5),
            SyntaxFixture.node(.throwStmt, lines: 6...6),
          ]
        )
      ),
      head: .absent(.fileDeleted)
    )
    let violations = await ControlFlowDeletionRule().evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("Deleted production file") == true)
    #expect(violations.first?.line == nil)
  }

  @Test("says nothing about a file whose change removed no lines at all")
  func silentWhenNothingWasRemoved() async {
    let violations = await evaluate(
      rule: ControlFlowDeletionRule(),
      base: [
        SyntaxFixture.node(.guardStmt, lines: 4...4),
        SyntaxFixture.node(.ifExpr, lines: 5...5),
        SyntaxFixture.node(.throwStmt, lines: 6...6),
      ],
      head: [],
      lines: [DiffLine(kind: .added, number: 4, text: "")]
    )

    #expect(violations.isEmpty)
  }

  // MARK: - error_handling_collapse

  @Test("flags a force-unwrap the change introduced")
  func flagsForceUnwrap() async {
    let violations = await evaluate(
      rule: UncheckedErrorPathRule(),
      base: [],
      head: [
        SyntaxFixture.node(.forceUnwrapExpr, lines: 5...5, name: "maybeValue")
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.line == 5)
    #expect(violations.first?.detail?.contains("maybeValue") == true)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("does not flag a force-unwrap the change never touched")
  func doesNotFlagUntouchedForceUnwrap() async {
    let existing = SyntaxFixture.node(.forceUnwrapExpr, lines: 9...9, name: "maybeValue")
    let violations = await evaluate(
      rule: UncheckedErrorPathRule(),
      base: [existing],
      head: [existing],
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )

    #expect(violations.isEmpty)
  }

  @Test("flags a multi-line catch that discards the error, and gives it a line")
  func flagsMultiLineSwallowedCatch() async {
    let swallowed = SyntaxFixture.node(
      .catchClause,
      lines: 5...7,
      children: [SyntaxFixture.node(.codeBlock, lines: 5...7)]
    )
    let violations = await evaluate(
      rule: UncheckedErrorPathRule(),
      base: [],
      head: [swallowed],
      lines: [
        DiffLine(kind: .added, number: 5, text: ""),
        DiffLine(kind: .added, number: 6, text: ""),
        DiffLine(kind: .added, number: 7, text: ""),
      ]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("silently discarded") == true)
    #expect(violations.first?.line == 5)
  }

  @Test("does not flag a catch that handles the error")
  func doesNotFlagAHandledCatch() async {
    let handled = SyntaxFixture.node(
      .catchClause,
      lines: 5...7,
      children: [
        SyntaxFixture.node(
          .codeBlock,
          lines: 5...7,
          children: [SyntaxFixture.call("log", line: 6)]
        )
      ]
    )
    let violations = await evaluate(
      rule: UncheckedErrorPathRule(),
      base: [],
      head: [handled],
      lines: [DiffLine(kind: .added, number: 6, text: "")]
    )

    #expect(violations.isEmpty)
  }

  @Test("leaves test paths alone on the tree as on the lines")
  func ignoresTestPaths() async {
    let context = TestSupport.context()
    let testPath = "Tests/ValidatorTests.swift"
    let fileDiff = SyntaxFixture.diff(
      path: testPath,
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )
    let syntax = SyntaxFixture.evidence(
      path: testPath,
      base: SyntaxFixture.tree(path: testPath, ref: .base, []),
      head: SyntaxFixture.tree(
        path: testPath,
        ref: .head,
        [SyntaxFixture.node(.forceUnwrapExpr, lines: 5...5, name: "maybeValue")]
      )
    )
    let violations = await UncheckedErrorPathRule().evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )

    #expect(violations.isEmpty)
  }

  // MARK: - Degradation

  @Test("degrades to the line matchers when the trees are unavailable")
  func degradesToLinesWhenUnavailable() async {
    let context = TestSupport.context()
    let fileDiff = TestSupport.fileDiff(path: path, added: ["    let value = maybeValue!"])
    let violations = await UncheckedErrorPathRule().evaluate(
      evidence: SyntaxFixture.bundle(
        fileDiff: fileDiff,
        syntax: SyntaxFixture.degradedEvidence(path: path),
        context: context
      ),
      context: context
    )

    #expect(violations.count == 1)
    #expect(violations.first?.evidence == .degradedDiff)
  }

  @Test("the compatibility facade passes the trees through to both rules")
  func facadeForwardsSyntacticEvidence() async {
    let context = TestSupport.context()
    let fileDiff = SyntaxFixture.diff(
      path: path,
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )
    let syntax = SyntaxFixture.evidence(
      path: path,
      base: SyntaxFixture.tree(path: path, ref: .base, []),
      head: SyntaxFixture.tree(
        path: path,
        ref: .head,
        [SyntaxFixture.node(.forceUnwrapExpr, lines: 5...5, name: "maybeValue")]
      )
    )
    let violations = await ProductionCodeDeletionRule().evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )

    #expect(violations.count == 1)
    #expect(violations.first?.evidence == .syntax)
    #expect(violations.first?.ruleID == UncheckedErrorPathRule.ruleID)
  }

  // MARK: - Helpers

  private func evaluate(
    rule: some Rule,
    base: [SyntaxNode],
    head: [SyntaxNode],
    lines: [DiffLine]
  ) async -> [Violation] {
    let context = TestSupport.context()
    let fileDiff = SyntaxFixture.diff(path: path, lines: lines)
    let syntax = SyntaxFixture.evidence(
      path: path,
      base: SyntaxFixture.tree(path: path, ref: .base, base),
      head: SyntaxFixture.tree(path: path, ref: .head, head)
    )
    return await rule.evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )
  }
}
