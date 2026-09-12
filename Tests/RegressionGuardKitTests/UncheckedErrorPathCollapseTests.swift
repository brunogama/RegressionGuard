import Foundation
import Testing

@testable import RegressionGuardKit

/// The two detections the AST-only rule catalog collapsed into `error_handling_collapse`: a
/// `try?` that discards the error, and a `guard` whose failure branch was reduced to a bare
/// `return`.
@Suite("Unchecked error path collapse tests")
struct UncheckedErrorPathCollapseTests {
  let rule = UncheckedErrorPathRule()
  let path = "Sources/Foo.swift"

  /// A `try?`, whose optionality is legible only through the node's spelling.
  private static func optionalTry(line: Int) -> SyntaxNode {
    SyntaxNode(kind: .tryExpr, span: LineSpan(line: line), name: "try?")
  }

  private static func plainTry(line: Int) -> SyntaxNode {
    SyntaxNode(kind: .tryExpr, span: LineSpan(line: line), name: "try")
  }

  /// `guard <condition> else { <body> }`.
  private static func guardStmt(
    condition: String,
    lines: ClosedRange<Int>,
    body: [SyntaxNode]
  ) -> SyntaxNode {
    SyntaxNode(
      kind: .guardStmt,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: condition,
      children: [
        SyntaxNode(
          kind: .codeBlock,
          span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
          children: body
        )
      ]
    )
  }

  private static func bareReturn(line: Int) -> SyntaxNode {
    SyntaxNode(kind: .returnStmt, span: LineSpan(line: line))
  }

  private static func throwStmt(line: Int) -> SyntaxNode {
    SyntaxNode(kind: .throwStmt, span: LineSpan(line: line), name: "StoreError.missing")
  }

  // MARK: - try?

  @Test("flags a try? the change introduced, which discards the error entirely")
  func flagsIntroducedOptionalTry() async {
    let violations = await evaluateFile(
      base: [],
      head: [Self.optionalTry(line: 5)],
      lines: [DiffLine(kind: .added, number: 5, text: "    let value = try? decode()")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.ruleID == "error_handling_collapse")
    #expect(violations.first?.line == 5)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("does not flag a plain try, which still propagates the error")
  func ignoresPlainTry() async {
    let violations = await evaluateFile(
      base: [],
      head: [Self.plainTry(line: 5)],
      lines: [DiffLine(kind: .added, number: 5, text: "    let value = try decode()")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a try? the change never touched")
  func ignoresUntouchedOptionalTry() async {
    let violations = await evaluateFile(
      base: [Self.optionalTry(line: 5)],
      head: [Self.optionalTry(line: 5)],
      lines: [DiffLine(kind: .added, number: 40, text: "// unrelated")]
    )

    #expect(violations.isEmpty)
  }

  // MARK: - guard reduced to a bare return

  @Test("flags a guard whose failure branch was reduced to a bare return")
  func flagsGuardReducedToBareReturn() async {
    let violations = await evaluateFile(
      base: [
        Self.guardStmt(condition: "let user", lines: 4...6, body: [Self.throwStmt(line: 5)])
      ],
      head: [
        Self.guardStmt(condition: "let user", lines: 4...6, body: [Self.bareReturn(line: 5)])
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "      return")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.detail?.contains("let user") == true)
  }

  /// `guard let x else { return }` is ordinary Swift. Flagging every one of them would drown the
  /// rule, so only a branch that used to do more counts.
  @Test("does not flag a guard that always returned bare")
  func ignoresGuardThatAlwaysReturnedBare() async {
    let unchanged = Self.guardStmt(
      condition: "let user",
      lines: 4...6,
      body: [Self.bareReturn(line: 5)]
    )
    let violations = await evaluateFile(
      base: [unchanged],
      head: [unchanged],
      lines: [DiffLine(kind: .added, number: 5, text: "      return")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a newly written guard with a bare return")
  func ignoresNewGuardWithBareReturn() async {
    let violations = await evaluateFile(
      base: [],
      head: [
        Self.guardStmt(condition: "let user", lines: 4...6, body: [Self.bareReturn(line: 5)])
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "      return")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a guard whose branch still throws")
  func ignoresGuardThatStillThrows() async {
    let violations = await evaluateFile(
      base: [
        Self.guardStmt(condition: "let user", lines: 4...6, body: [Self.throwStmt(line: 5)])
      ],
      head: [
        Self.guardStmt(condition: "let user", lines: 4...6, body: [Self.throwStmt(line: 5)])
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "      throw StoreError.missing")]
    )

    #expect(violations.isEmpty)
  }

  // MARK: - the empty catch, read through both projection shapes

  @Test("flags an empty catch whose body is an empty statement list")
  func flagsEmptyCatchBehindStatementList() async {
    let emptyCatch = SyntaxNode(
      kind: .catchClause,
      span: LineSpan(start: 5, end: 7),
      children: [
        SyntaxNode(
          kind: .codeBlock,
          span: LineSpan(start: 5, end: 7),
          children: [
            SyntaxNode(kind: .codeBlockItemList, span: LineSpan(start: 6, end: 6))
          ]
        )
      ]
    )
    let violations = await evaluateFile(
      base: [],
      head: [emptyCatch],
      lines: [DiffLine(kind: .added, number: 5, text: "    } catch {")]
    )

    #expect(violations.count == 1)
  }

  private func evaluateFile(
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
