import Testing
@testable import RegressionGuardKit

@Suite("Disabled or skipped test rule tests")
struct DisabledOrSkippedTestRuleTests {
  let rule = DisabledOrSkippedTestRule()

  @Test("flags a skip thrown in a test")
  func flagsSkipAddedToATest() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["    throw XCTSkip(\"flaky\")"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.count == 1)
    #expect(violations.first?.ruleID == DisabledOrSkippedTestRule.ruleID)
  }

  @Test("does not flag a test named after a skip marker")
  func doesNotFlagATestNamedAfterASkipMarker() async {
    // A test named for what it checks is not a skipped test; the marker is in its own name.
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["  func testFlagsXCTSkipAddedToATest() async {"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty, "expected no violations, got: \(violations)")
  }

  @Test("flags a skip inside a single-line test body")
  func flagsASkipInsideASingleLineTestBody() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      added: ["  func testSomething() throws { throw XCTSkip(\"flaky\") }"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.count == 1)
  }

  @Test("flags a Swift Testing disabled trait")
  func flagsSwiftTestingDisabledTrait() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["@Test func testImportantThing() {"],
      added: ["@Test(.disabled(\"todo\")) func testImportantThing() {"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.count == 1)
  }

  @Test("flags commented-out test code")
  func flagsCommentedOutTestCode() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.value, 42)"],
      added: ["    // XCTAssertEqual(sut.value, 42)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.count == 1)
  }

  @Test("flags a whole test file deletion")
  func flagsWholeTestFileDeletion() async {
    let diff = TestSupport.fileDiff(path: "Tests/FooTests.swift", isDeleted: true)
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.count == 1)
  }

  @Test("ignores production files")
  func ignoresProductionFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      added: ["    throw XCTSkip(\"not a real test file\")"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }

  @Test("an ordinary test edit does not trigger a false positive")
  func ordinaryTestEditDoesNotTriggerAFalsePositive() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    XCTAssertEqual(sut.value, 41)"],
      added: ["    XCTAssertEqual(sut.value, 42)"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }
}
