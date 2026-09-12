import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Weakened assertion rule syntax tests")
struct WeakenedAssertionRuleSyntaxTests {
  let rule = WeakenedAssertionRule()
  let path = "Tests/FooTests.swift"

  // MARK: - Tautologies the text matcher lets through

  @Test(
    "flags a tautology the hardcoded spellings miss",
    arguments: [
      SyntaxFixture.call(
        "XCTAssertTrue",
        line: 5,
        arguments: [SyntaxFixture.literal(.booleanLiteralExpr, "true", line: 5)]
      ),
      SyntaxFixture.macro(
        "expect",
        line: 5,
        arguments: [
          SyntaxFixture.comparison(
            [
              SyntaxFixture.literal(.integerLiteralExpr, "1", line: 5),
              SyntaxFixture.literal(.integerLiteralExpr, "1", line: 5),
            ],
            line: 5
          )
        ]
      ),
      SyntaxFixture.call(
        "XCTAssertEqual",
        line: 5,
        arguments: [
          SyntaxFixture.literal(.integerLiteralExpr, "2", line: 5),
          SyntaxFixture.literal(.integerLiteralExpr, "2", line: 5),
        ]
      ),
    ]
  )
  func flagsTautologiesTheTextMatcherMisses(assertion: SyntaxNode) async {
    let violations = await evaluate(replacingAssertionWith: assertion)

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("never fail") == true)
    #expect(violations.first?.line == 5)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("flags a tautology whose callee is projected as a child of the call")
  func flagsTautologyWhenTheCalleeIsAChild() async {
    let violations = await evaluate(
      replacingAssertionWith: SyntaxFixture.callWithCalleeChild(
        "XCTAssertTrue",
        line: 5,
        arguments: [SyntaxFixture.literal(.booleanLiteralExpr, "true", line: 5)]
      )
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("never fail") == true)
  }

  @Test("still reads a real assertion as healthy when the callee is a child")
  func realAssertionStaysHealthyWhenTheCalleeIsAChild() async {
    let violations = await evaluate(
      replacingAssertionWith: SyntaxFixture.callWithCalleeChild(
        "XCTAssertEqual",
        line: 5,
        arguments: [
          SyntaxFixture.member("total", line: 5),
          SyntaxFixture.literal(.integerLiteralExpr, "43", line: 5),
        ]
      )
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag an assertion that reads a value under test")
  func doesNotFlagARealAssertion() async {
    let violations = await evaluate(
      replacingAssertionWith: SyntaxFixture.call(
        "XCTAssertEqual",
        line: 5,
        arguments: [
          SyntaxFixture.member("total", line: 5),
          SyntaxFixture.literal(.integerLiteralExpr, "43", line: 5),
        ]
      )
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag an unconditional XCTFail, whose literal message is correct")
  func doesNotFlagUnconditionalFailure() async {
    let violations = await evaluate(
      replacingAssertionWith: SyntaxFixture.call(
        "XCTFail",
        line: 5,
        arguments: [SyntaxFixture.literal(.stringLiteralExpr, "not reached", line: 5)]
      )
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a tautology the change never touched")
  func doesNotFlagUntouchedTautology() async {
    let tautology = SyntaxFixture.call(
      "XCTAssertTrue",
      line: 9,
      arguments: [SyntaxFixture.literal(.booleanLiteralExpr, "true", line: 9)]
    )
    let assertion = SyntaxFixture.call(
      "XCTAssertEqual",
      line: 5,
      arguments: [SyntaxFixture.member("total", line: 5)]
    )
    let violations = await evaluateFile(
      base: [assertion, tautology],
      head: [assertion, tautology],
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )

    #expect(violations.isEmpty)
  }

  // MARK: - Removals counted as calls rather than lines

  @Test("counts a multi-line assertion once rather than once per line")
  func countsMultiLineAssertionOnce() async {
    let spread = SyntaxFixture.call(
      "XCTAssertEqual",
      lines: 5...7,
      arguments: [SyntaxFixture.member("total", line: 6)]
    )
    let violations = await evaluateFile(
      base: [spread],
      head: [
        SyntaxFixture.call(
          "XCTAssertEqual",
          line: 5,
          arguments: [
            SyntaxFixture.member("total", line: 5)
          ]
        )
      ],
      lines: [
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .removed, number: 6, text: ""),
        DiffLine(kind: .removed, number: 7, text: ""),
        DiffLine(kind: .added, number: 5, text: ""),
      ]
    )

    #expect(violations.isEmpty)
  }

  @Test("flags assertions that left the file without replacement")
  func flagsNetRemoval() async {
    let first = SyntaxFixture.call(
      "XCTAssertEqual",
      line: 5,
      arguments: [
        SyntaxFixture.member("total", line: 5)
      ]
    )
    let second = SyntaxFixture.call(
      "XCTAssertTrue",
      line: 6,
      arguments: [
        SyntaxFixture.reference("isValid", line: 6)
      ]
    )
    let violations = await evaluateFile(
      base: [first, second],
      head: [first],
      lines: [DiffLine(kind: .removed, number: 6, text: "")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("1 assertion(s) removed") == true)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("counts the assertions a deleted test file was making")
  func countsDeletedFileAssertions() async {
    let base = SyntaxFixture.tree(
      path: path,
      ref: .base,
      [
        SyntaxFixture.call(
          "XCTAssertEqual",
          line: 5,
          arguments: [
            SyntaxFixture.member("total", line: 5)
          ]
        ),
        SyntaxFixture.macro(
          "expect",
          line: 6,
          arguments: [
            SyntaxFixture.reference("isValid", line: 6)
          ]
        ),
      ]
    )
    let fileDiff = SyntaxFixture.diff(
      path: path,
      lines: [DiffLine(kind: .removed, number: 5, text: "")],
      isDeleted: true
    )
    let syntax = SyntacticFileEvidence(
      path: path,
      base: .parsed(base),
      head: .absent(.fileDeleted)
    )
    let violations = await rule.evaluate(
      evidence: SyntaxFixture.bundle(
        fileDiff: fileDiff,
        syntax: syntax,
        context: TestSupport.context()
      ),
      context: TestSupport.context()
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("contained 2 assertion(s)") == true)
    #expect(violations.first?.line == nil)
    #expect(violations.first?.evidence == .syntax)
  }

  // MARK: - Degradation

  @Test("falls back to the line matcher when a tree is unavailable, and says so")
  func degradesToLinesWhenUnavailable() async {
    let fileDiff = TestSupport.fileDiff(
      path: path,
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertTrue(true)"]
    )
    let context = TestSupport.context()
    let violations = await rule.evaluate(
      evidence: SyntaxFixture.bundle(
        fileDiff: fileDiff,
        syntax: SyntaxFixture.degradedEvidence(path: path),
        context: context
      ),
      context: context
    )

    #expect(!violations.isEmpty)
    #expect(violations.allSatisfy { $0.evidence == .degradedDiff })
  }

  // MARK: - Helpers

  /// A file whose one assertion on line 5 was rewritten by the change.
  private func evaluate(replacingAssertionWith assertion: SyntaxNode) async -> [Violation] {
    await evaluateFile(
      base: [
        SyntaxFixture.call(
          "XCTAssertEqual",
          line: 5,
          arguments: [SyntaxFixture.member("total", line: 5)]
        )
      ],
      head: [assertion],
      lines: [
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .added, number: 5, text: ""),
      ]
    )
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
