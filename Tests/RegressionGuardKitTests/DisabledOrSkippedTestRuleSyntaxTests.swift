import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Disabled or skipped test rule syntax tests")
struct DisabledOrSkippedTestRuleSyntaxTests {
  let rule = DisabledOrSkippedTestRule()
  let path = "Tests/FooTests.swift"

  // MARK: - Skip markers as nodes

  @Test("flags a disabling trait and names the test it switched off")
  func flagsDisablingTrait() async {
    let disabled = SyntaxFixture.function(
      "answers",
      lines: 4...6,
      attributes: [
        SyntaxFixture.attribute(
          "Test",
          line: 4,
          arguments: [SyntaxFixture.trait("disabled", line: 4)]
        )
      ]
    )
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("answers", lines: 4...6)],
      head: [disabled],
      lines: [DiffLine(kind: .added, number: 4, text: "")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.line == 4)
    #expect(violations.first?.detail?.contains("answers") == true)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("flags a throw of XCTSkip inside a test body")
  func flagsSkipCall() async {
    let head = SyntaxFixture.function(
      "testAnswer",
      lines: 4...7,
      body: [
        SyntaxFixture.node(
          .throwStmt,
          lines: 5...5,
          children: [SyntaxFixture.call("XCTSkip", line: 5)]
        )
      ]
    )
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("testAnswer", lines: 4...7)],
      head: [head],
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.line == 5)
  }

  @Test("does not flag a test merely named after the marker it checks for")
  func doesNotFlagATestNamedAfterTheMarker() async {
    let named = SyntaxFixture.function("testFlagsXCTSkipAddedToATest", lines: 4...6)
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("testFlagsXCTSkipAddedToATest", lines: 4...6)],
      head: [named],
      lines: [DiffLine(kind: .added, number: 5, text: "")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a test that was already disabled before this change")
  func doesNotFlagPreExistingDisable() async {
    let disabled = SyntaxFixture.function(
      "answers",
      lines: 4...8,
      attributes: [
        SyntaxFixture.attribute(
          "Test",
          line: 4,
          arguments: [SyntaxFixture.trait("disabled", line: 4)]
        )
      ]
    )
    let violations = await evaluateFile(
      base: [disabled],
      head: [disabled],
      lines: [DiffLine(kind: .added, number: 6, text: "")]
    )

    #expect(violations.isEmpty)
  }

  // MARK: - Test function identity off the trees

  @Test("flags a test function that left the file")
  func flagsRemovedTestFunction() async {
    let violations = await evaluateFile(
      base: [
        SyntaxFixture.function("testAnswer", lines: 4...6),
        SyntaxFixture.function("testOther", lines: 8...10),
      ],
      head: [SyntaxFixture.function("testOther", lines: 4...6)],
      lines: [
        DiffLine(kind: .removed, number: 4, text: ""),
        DiffLine(kind: .removed, number: 5, text: ""),
        DiffLine(kind: .removed, number: 6, text: ""),
      ]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("`testAnswer` was removed") == true)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("flags a test that lost its @Test attribute while keeping its name")
  func flagsLostTestIdentity() async {
    let violations = await evaluateFile(
      base: [
        SyntaxFixture.function(
          "answers",
          lines: 4...6,
          attributes: [SyntaxFixture.attribute("Test", line: 4)]
        )
      ],
      head: [SyntaxFixture.function("answers", lines: 4...6)],
      lines: [DiffLine(kind: .removed, number: 4, text: "")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("lost its test identity") == true)
  }

  @Test("sees a @Test attribute separated from its declaration by a doc comment")
  func seesAttributeAcrossADocComment() async {
    let annotated = SyntaxFixture.function(
      "answers",
      lines: 4...9,
      attributes: [SyntaxFixture.attribute("Test", line: 4)]
    )
    let violations = await evaluateFile(
      base: [annotated],
      head: [annotated],
      lines: [DiffLine(kind: .added, number: 8, text: "")]
    )

    #expect(violations.isEmpty)
  }

  // MARK: - Detections that stay on the diff

  @Test("still flags a deleted test file with no tree involved")
  func stillFlagsDeletedTestFile() async {
    let context = TestSupport.context()
    let fileDiff = SyntaxFixture.diff(
      path: path,
      lines: [DiffLine(kind: .removed, number: 1, text: "")],
      isDeleted: true
    )
    let syntax = SyntacticFileEvidence(
      path: path,
      base: .parsed(SyntaxFixture.tree(path: path, ref: .base, [])),
      head: .absent(.fileDeleted)
    )
    let violations = await rule.evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("deleted instead of fixed") == true)
    #expect(violations.first?.evidence == .diff)
  }

  @Test("still flags a test commented out in place when a tree is available")
  func stillFlagsCommentedOutTest() async {
    let context = TestSupport.context()
    let fileDiff = TestSupport.fileDiff(
      path: path,
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    // XCTAssertEqual(sut.total, 42)"]
    )
    let syntax = SyntaxFixture.evidence(
      path: path,
      base: SyntaxFixture.tree(path: path, ref: .base, []),
      head: SyntaxFixture.tree(path: path, ref: .head, [])
    )
    let violations = await rule.evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )

    #expect(violations.count == 1)
    #expect(violations.first?.message.contains("commented out") == true)
    #expect(violations.first?.evidence == .diff)
  }

  // MARK: - Degradation

  @Test("falls back to the line matcher when a tree is unavailable, and says so")
  func degradesToLinesWhenUnavailable() async {
    let context = TestSupport.context()
    let fileDiff = TestSupport.fileDiff(
      path: path,
      added: ["    throw XCTSkip(\"flaky\")"]
    )
    let violations = await rule.evaluate(
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

  // MARK: - Helpers

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
