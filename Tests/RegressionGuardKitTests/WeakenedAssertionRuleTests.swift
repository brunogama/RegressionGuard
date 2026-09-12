import Testing
@testable import RegressionGuardKit

@Suite("Weakened assertion rule tests")
struct WeakenedAssertionRuleTests {
  let rule = WeakenedAssertionRule()

  @Test("flags a tautological replacement")
  func flagsTautologicalReplacement() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertTrue(true)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(!violations.isEmpty)
    #expect(violations.contains { $0.message.contains("never fail") })
  }

  @Test("flags a net assertion removal without replacement")
  func flagsNetAssertionRemovalWithoutReplacement() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: [
        "    XCTAssertEqual(sut.total, 42)",
        "    XCTAssertTrue(sut.isValid)",
      ],
      added: []
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(!violations.isEmpty)
  }

  @Test("does not flag assertions moved one for one")
  func doesNotFlagAssertionsMovedOneForOne() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.total, 42)"],
      added: ["    XCTAssertEqual(sut.total, 43)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }

  @Test("ignores production files")
  func ignoresProductionFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    XCTAssertTrue(true)"],
      added: []
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }
}
