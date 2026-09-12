import Foundation
import Testing

@testable import RegressionGuardKit

/// `withKnownIssue` does not skip a test: the test runs, its assertions run, and their failure is
/// absorbed and reported as expected. That is a different harm from a disabled test, and a
/// legitimate practice when it carries a tracking reference, which is why it is its own advisory
/// family rather than a blocking skip marker.
@Suite("Known issue suppression rule tests")
struct KnownIssueSuppressionRuleTests {
  let rule = KnownIssueSuppressionRule()
  let path = "Tests/FooTests.swift"

  /// `withKnownIssue { ... }` spanning `lines`, with its trailing closure as a child so the
  /// call's own lines are just the opening one.
  private static func withKnownIssue(lines: ClosedRange<Int>) -> SyntaxNode {
    SyntaxNode(
      kind: .functionCallExpr,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: "withKnownIssue",
      children: [
        SyntaxNode(
          kind: .closureExpr,
          span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
          children: [SyntaxFixture.call("expect", line: lines.lowerBound + 1)]
        )
      ]
    )
  }

  @Test("flags a known-issue suppression the change introduced")
  func flagsIntroducedSuppression() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("answers", lines: 4...8)],
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [Self.withKnownIssue(lines: 5...7)]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    withKnownIssue {")]
    )

    #expect(violations.count == 1)
    #expect(violations.first?.ruleID == "known_issue_suppression")
    #expect(violations.first?.line == 5)
    #expect(violations.first?.severity == .warning)
    #expect(violations.first?.evidence == .syntax)
  }

  @Test("names the test whose failure is being absorbed")
  func namesTheTest() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("answers", lines: 4...8)],
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [Self.withKnownIssue(lines: 5...7)]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    withKnownIssue {")]
    )

    #expect(violations.first?.detail?.contains("answers") == true)
  }

  @Test("does not flag editing the body of a suppression that was already there")
  func ignoresBodyEditUnderExistingSuppression() async {
    let suppressed = SyntaxFixture.function(
      "answers",
      lines: 4...8,
      body: [Self.withKnownIssue(lines: 5...7)]
    )
    let violations = await evaluateFile(
      base: [suppressed],
      head: [suppressed],
      lines: [DiffLine(kind: .added, number: 6, text: "      #expect(total == 3)")]
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag production code, since only a test can suppress its own failure")
  func ignoresProductionPaths() async {
    let context = TestSupport.context()
    let productionPath = "Sources/Foo.swift"
    let fileDiff = SyntaxFixture.diff(
      path: productionPath,
      lines: [DiffLine(kind: .added, number: 5, text: "    withKnownIssue {")]
    )
    let syntax = SyntaxFixture.evidence(
      path: productionPath,
      base: SyntaxFixture.tree(path: productionPath, ref: .base, []),
      head: SyntaxFixture.tree(
        path: productionPath,
        ref: .head,
        [Self.withKnownIssue(lines: 5...7)]
      )
    )
    let violations = await rule.evaluate(
      evidence: SyntaxFixture.bundle(fileDiff: fileDiff, syntax: syntax, context: context),
      context: context
    )

    #expect(violations.isEmpty)
  }

  @Test("does not flag a call whose name merely starts the same way")
  func ignoresSimilarlyNamedCall() async {
    let violations = await evaluateFile(
      base: [SyntaxFixture.function("answers", lines: 4...8)],
      head: [
        SyntaxFixture.function(
          "answers",
          lines: 4...8,
          body: [SyntaxFixture.call("withKnownIssueTracker", line: 5)]
        )
      ],
      lines: [DiffLine(kind: .added, number: 5, text: "    withKnownIssueTracker()")]
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
