import XCTest
@testable import RegressionGuardKit

final class WeakenedAssertionRuleTests: XCTestCase {
  let rule = WeakenedAssertionRule()

  func testFlagsTautologicalReplacement() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertTrue(true)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertFalse(violations.isEmpty)
    XCTAssertTrue(violations.contains { $0.message.contains("never fail") })
  }

  func testFlagsNetAssertionRemovalWithoutReplacement() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: [
        "    XCTAssertEqual(sut.total, 42)",
        "    XCTAssertTrue(sut.isValid)",
      ],
      added: []
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertFalse(violations.isEmpty)
  }

  func testDoesNotFlagAssertionsMovedOneForOne() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertEqual(sut.total, 43)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testIgnoresProductionFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    XCTAssertTrue(true)"],
      added: []
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
