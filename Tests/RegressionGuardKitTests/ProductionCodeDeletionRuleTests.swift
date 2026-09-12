import XCTest
@testable import RegressionGuardKit

final class ProductionCodeDeletionRuleTests: XCTestCase {
  let rule = ProductionCodeDeletionRule()

  func testFlagsForceUnwrapIntroduced() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    guard let value = maybeValue else { return nil }"],
      added: ["    let value = maybeValue!"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.contains { $0.message.contains("Force-unwrap") })
  }

  func testFlagsEmptyCatchBlock() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    } catch { log.error(error) }"],
      added: ["    } catch {}"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.contains { $0.message.contains("Empty") })
  }

  func testFlagsLopsidedControlFlowDeletion() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: [
        "    if !isValid { throw ValidationError.invalid }",
        "    guard let user else { throw AuthError.missingUser }",
        "    for item in items { try validate(item) }",
      ],
      added: []
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertFalse(violations.isEmpty)
  }

  func testDoesNotFlagGenuineRefactor() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    if !isValid { throw ValidationError.invalid }"],
      added: ["    guard isValid else { throw ValidationError.invalid }"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testIgnoresTestFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    guard let value = maybeValue else { return nil }"],
      added: ["    let value = maybeValue!"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testDoesNotFlagBooleanNegationOrNotEqual() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: [],
      added: [
        "    if !isValid { return }",
        "    guard a != b else { return }",
      ]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
