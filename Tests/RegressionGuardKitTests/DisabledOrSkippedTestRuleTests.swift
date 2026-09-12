import XCTest
@testable import RegressionGuardKit

final class DisabledOrSkippedTestRuleTests: XCTestCase {
  let rule = DisabledOrSkippedTestRule()

  func testFlagsXCTSkipAddedToATest() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["    throw XCTSkip(\"flaky\")"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
    XCTAssertEqual(violations.first?.ruleID, DisabledOrSkippedTestRule.ruleID)
  }

  func testFlagsSwiftTestingDisabledTrait() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["@Test func testImportantThing() {"],
      added: ["@Test(.disabled(\"todo\")) func testImportantThing() {"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testFlagsCommentedOutTestCode() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.value, 42)"],
      added: ["    // XCTAssertEqual(sut.value, 42)"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testFlagsWholeTestFileDeletion() {
    let diff = TestSupport.fileDiff(path: "Tests/FooTests.swift", isDeleted: true)
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
  }

  func testIgnoresProductionFiles() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      added: ["    throw XCTSkip(\"not a real test file\")"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testOrdinaryTestEditDoesNotTriggerAFalsePositive() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.value, 41)"],
      added: ["    XCTAssertEqual(sut.value, 42)"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
