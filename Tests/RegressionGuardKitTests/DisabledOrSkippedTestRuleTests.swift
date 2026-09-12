import XCTest
@testable import RegressionGuardKit

final class DisabledOrSkippedTestRuleTests: XCTestCase {
  let rule = DisabledOrSkippedTestRule()

  func testFlagsXCTSkipAddedToATest() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["    throw XCTSkip(\"flaky\")"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
    XCTAssertEqual(violations.first?.ruleID, DisabledOrSkippedTestRule.ruleID)
  }

  func testDoesNotFlagATestNamedAfterASkipMarker() async {
    // A test named for what it checks is not a skipped test; the marker is in its own name.
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["  func testFlagsXCTSkipAddedToATest() async {"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty, "expected no violations, got: \(violations)")
  }

  func testFlagsASkipInsideASingleLineTestBody() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["  func testSomething() throws { throw XCTSkip(\"flaky\") }"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testFlagsSwiftTestingDisabledTrait() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["@Test func testImportantThing() {"],
      added: ["@Test(.disabled(\"todo\")) func testImportantThing() {"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testFlagsCommentedOutTestCode() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.value, 42)"],
      added: ["    // XCTAssertEqual(sut.value, 42)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testFlagsWholeTestFileDeletion() async {
    let diff = TestSupport.fileDiff(path: "Tests/FooTests.swift", isDeleted: true)
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testIgnoresProductionFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      added: ["    throw XCTSkip(\"not a real test file\")"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testOrdinaryTestEditDoesNotTriggerAFalsePositive() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.value, 41)"],
      added: ["    XCTAssertEqual(sut.value, 42)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
