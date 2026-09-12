import XCTest
@testable import RegressionGuardKit

final class WeakenedAssertionRuleTests: XCTestCase {
  let rule = WeakenedAssertionRule()

  func testFlagsTautologicalReplacement() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertTrue(true)"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertFalse(violations.isEmpty)
    XCTAssertTrue(violations.contains { $0.message.contains("never fail") })
  }

  func testFlagsNetAssertionRemovalWithoutReplacement() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: [
        "    XCTAssertEqual(sut.total, 42)",
        "    XCTAssertTrue(sut.isValid)",
      ],
      added: []
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertFalse(violations.isEmpty)
  }

  func testDoesNotFlagAssertionsMovedOneForOne() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertEqual(sut.total, 43)"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testIgnoresProductionFiles() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    XCTAssertTrue(true)"],
      added: []
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
