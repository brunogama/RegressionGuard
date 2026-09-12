import XCTest
@testable import RegressionGuardKit

final class ProductionCodeDeletionRuleTests: XCTestCase {
  let rule = ProductionCodeDeletionRule()

  func testFlagsForceUnwrapIntroduced() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    guard let value = maybeValue else { return nil }"],
      added: ["    let value = maybeValue!"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.contains { $0.message.contains("Force-unwrap") })
  }

  func testFlagsEmptyCatchBlock() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    } catch { log.error(error) }"],
      added: ["    } catch {}"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.contains { $0.message.contains("Empty") })
  }

  func testFlagsLopsidedControlFlowDeletion() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: [
        "    if !isValid { throw ValidationError.invalid }",
        "    guard let user else { throw AuthError.missingUser }",
        "    for item in items { try validate(item) }",
      ],
      added: []
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertFalse(violations.isEmpty)
  }

  func testDoesNotFlagGenuineRefactor() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    if !isValid { throw ValidationError.invalid }"],
      added: ["    guard isValid else { throw ValidationError.invalid }"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testIgnoresTestFiles() {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    guard let value = maybeValue else { return nil }"],
      added: ["    let value = maybeValue!"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }

  func testDoesNotFlagBooleanNegationOrNotEqual() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: [],
      added: [
        "    if !isValid { return }",
        "    guard a != b else { return }",
      ]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
