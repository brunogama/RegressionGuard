import Foundation
import Testing

@testable import RegressionGuardKit

/// A function that did real work and now traps or returns a constant has had its behaviour
/// removed while keeping its signature, so every caller still compiles and the type checker says
/// nothing.
@Suite("Implementation stubbed rule tests")
struct ImplementationStubbedRuleTests {
  let rule = ImplementationStubbedRule()
  let path = "Sources/Foo.swift"

  private static func realBody(lines: ClosedRange<Int>) -> [SyntaxNode] {
    [
      SyntaxNode(
        kind: .ifExpr,
        span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
        name: "total > 0"
      ),
      SyntaxNode(kind: .returnStmt, span: LineSpan(line: lines.upperBound), name: "total"),
    ]
  }

  @Test("flags a real body replaced by a trap")
  func flagsBodyReplacedByTrap() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("total", lines: 4...8, body: Self.realBody(lines: 5...7))],
      head: [
        SyntaxFixture.function(
          "total",
          lines: 4...6,
          body: [SyntaxFixture.call("fatalError", line: 5)]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    fatalError(\"unimplemented\")")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.ruleID == "implementation_stubbed")
    #expect(violations.first?.severity == .warning)
    #expect(violations.first?.detail?.contains("total") == true)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("flags a real body replaced by a constant return")
  func flagsBodyReplacedByConstantReturn() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("total", lines: 4...8, body: Self.realBody(lines: 5...7))],
      head: [
        SyntaxFixture.function(
          "total",
          lines: 4...6,
          body: [
            SyntaxNode(
              kind: .returnStmt,
              span: LineSpan(line: 5),
              children: [SyntaxNode(kind: .nilLiteralExpr, span: LineSpan(line: 5))]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    return nil")]
    )

    #expect(violations.count == 1)
  }

  /// The counterpart fixture: statements wrapped in the list node swift-syntax actually uses.
  /// A rule reading the block's children directly sees one opaque list here, finds no trap, and
  /// reports nothing - silence, which is why this shape gets its own test.
  @Test("flags a stub whose statements are wrapped in a code-block item list")
  func flagsStubBehindStatementList() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("total", lines: 4...8, body: Self.realBody(lines: 5...7))],
      head: [
        SyntaxFixture.function(
          "total",
          lines: 4...6,
          body: [
            SyntaxNode(
              kind: .codeBlockItemList,
              span: LineSpan(line: 5),
              children: [SyntaxFixture.call("fatalError", line: 5)]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    fatalError(\"unimplemented\")")]
    )

    #expect(violations.count == 1)
  }

  @Test("does not flag a function that already trapped before the change")
  func ignoresPreexistingTrap() async {
    let stub = SyntaxFixture.function(
      "total",
      lines: 4...6,
      body: [SyntaxFixture.call("fatalError", line: 5)]
    )
    let violations = await evaluateFile(
      base: [stub],
      head: [stub],
      lines: [DiffLine(kind: .added, number: 4, text: "  func total() -> Int {")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a newly added stub, since no behaviour was removed")
  func ignoresNewlyAddedStub() async {
    let violations = await evaluateFile(
      base: [],
      head: [
        SyntaxFixture.function(
          "decode",
          lines: 4...6,
          body: [SyntaxFixture.call("fatalError", line: 5)]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    fatalError(\"init(coder:)\")")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a body that still returns a computed value")
  func ignoresComputedReturn() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("total", lines: 4...8, body: Self.realBody(lines: 5...7))],
      head: [
        SyntaxFixture.function(
          "total",
          lines: 4...6,
          body: [
            SyntaxNode(
              kind: .returnStmt,
              span: LineSpan(line: 5),
              children: [SyntaxNode(kind: .declReferenceExpr, span: LineSpan(line: 5))]
            )
          ]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    return total")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a trap the change never touched")
  func ignoresUntouchedStub() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("total", lines: 4...8, body: Self.realBody(lines: 5...7))],
      head: [
        SyntaxFixture.function(
          "total",
          lines: 4...6,
          body: [SyntaxFixture.call("fatalError", line: 5)]
        )
      ],
      lines: [DiffLine(kind: .added, number: 40, text: "// unrelated")]
    )

    #expect(violations.isEmpty)
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
