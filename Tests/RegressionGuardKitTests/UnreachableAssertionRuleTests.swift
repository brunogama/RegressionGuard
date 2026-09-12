import Foundation
import Testing

@testable import RegressionGuardKit

/// An assertion that cannot run constrains nothing, exactly like one that cannot fail. Syntax
/// cannot decide reachability in general, so this only claims the two cases it can prove: an
/// assertion under a literally false condition, and one sitting after an unconditional exit in
/// its own block.
@Suite("Unreachable assertion rule tests")
struct UnreachableAssertionRuleTests {
  let rule = UnreachableAssertionRule()
  let path = "Tests/FooTests.swift"

  private static func assertion(line: Int) -> SyntaxNode {
    SyntaxFixture.call(
      "expect",
      line: line,
      arguments: [SyntaxNode(kind: .declReferenceExpr, span: LineSpan(line: line))]
    )
  }

  @Test("flags an assertion moved under a literally false condition")
  func flagsAssertionUnderFalseCondition() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...9,
          body: [
            SyntaxNode(
              kind: .ifExpr,
              span: LineSpan(start: 5, end: 8),
              children: [
                SyntaxNode(kind: .booleanLiteralExpr, span: LineSpan(line: 5), name: "false"),
                SyntaxNode(
                  kind: .codeBlock,
                  span: LineSpan(start: 5, end: 8),
                  children: [Self.assertion(line: 6)]
                ),
              ]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    if false {")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.ruleID == "unreachable_assertion")
    #expect(violations.first?.severity == .warning)
    #expect(violations.first?.line == 6)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("flags an assertion left after an unconditional return in the same block")
  func flagsAssertionAfterReturn() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [
            SyntaxNode(kind: .returnStmt, span: LineSpan(line: 5)),
            Self.assertion(line: 6),
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    return")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.line == 6)
  }

  /// The other projection shape. Reading the block's children directly yields one list node here,
  /// no exit is ever found, and the rule goes quiet rather than wrong.
  @Test("flags a stranded assertion whose statements sit in a code-block item list")
  func flagsStrandedAssertionBehindStatementList() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [
            SyntaxNode(
              kind: .codeBlockItemList,
              span: LineSpan(start: 5, end: 6),
              children: [
                SyntaxNode(kind: .returnStmt, span: LineSpan(line: 5)),
                Self.assertion(line: 6),
              ]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    return")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.line == 6)
  }

  @Test("does not flag an assertion before the unconditional exit")
  func ignoresAssertionBeforeReturn() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [
            Self.assertion(line: 5),
            SyntaxNode(kind: .returnStmt, span: LineSpan(line: 6)),
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 6, text: "    return")]
    )

    #expect(violations.isEmpty)
  }

  /// swift-syntax nests a condition as `ConditionElementList` -> `ConditionElement` -> literal.
  /// Reading the branch's direct children finds no literal here and the rule goes quiet.
  @Test("flags an assertion under a false condition nested in a condition list")
  func flagsAssertionUnderNestedFalseCondition() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...9,
          body: [
            SyntaxNode(
              kind: .ifExpr,
              span: LineSpan(start: 5, end: 8),
              children: [
                SyntaxNode(
                  kind: .codeBlockItemList,
                  span: LineSpan(line: 5),
                  children: [
                    SyntaxNode(kind: .booleanLiteralExpr, span: LineSpan(line: 5), name: "false")
                  ]
                ),
                SyntaxNode(
                  kind: .codeBlock,
                  span: LineSpan(start: 5, end: 8),
                  children: [Self.assertion(line: 6)]
                ),
              ]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    if false {")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.line == 6)
  }

  /// The `else` of an `if false` is the one branch that always runs.
  @Test("does not flag an assertion in the else of a false condition")
  func ignoresElseBranchOfFalseCondition() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...11,
          body: [
            SyntaxNode(
              kind: .ifExpr,
              span: LineSpan(start: 5, end: 10),
              children: [
                SyntaxNode(kind: .booleanLiteralExpr, span: LineSpan(line: 5), name: "false"),
                SyntaxNode(kind: .codeBlock, span: LineSpan(start: 5, end: 7)),
                SyntaxNode(
                  kind: .codeBlock,
                  span: LineSpan(start: 8, end: 10),
                  children: [Self.assertion(line: 9)]
                ),
              ]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    if false {")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag an assertion under an ordinary condition")
  func ignoresOrdinaryCondition() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...9,
          body: [
            SyntaxNode(
              kind: .ifExpr,
              span: LineSpan(start: 5, end: 8),
              children: [
                SyntaxNode(kind: .declReferenceExpr, span: LineSpan(line: 5), name: "isEnabled"),
                SyntaxNode(
                  kind: .codeBlock,
                  span: LineSpan(start: 5, end: 8),
                  children: [Self.assertion(line: 6)]
                ),
              ]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    if isEnabled {")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag an unreachable assertion the change never touched")
  func ignoresUntouchedRegion() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [
            SyntaxNode(kind: .returnStmt, span: LineSpan(line: 5)),
            Self.assertion(line: 6),
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 40, text: "// unrelated")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a non-assertion left after a return")
  func ignoresNonAssertion() async {
    let violations = await evaluateFile(
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [
            SyntaxNode(kind: .returnStmt, span: LineSpan(line: 5)),
            SyntaxFixture.call("cleanUp", line: 6),
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    return")]
    )

    #expect(violations.isEmpty)
  }

  private func evaluateFile(head: [SyntaxNode], lines: [DiffLine]) async -> [Violation] {
    let context = TestSupport.context()
    let fileDiff = SyntaxFixture.diff(path: path, lines: lines)
    let syntax = SyntaxFixture.evidence(
      path: path,
      base: SyntaxFixture.tree(path: path, ref: .base, []),
      head: SyntaxFixture.tree(path: path, ref: .head, head)
    )
    return await rule.evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )
  }
}
