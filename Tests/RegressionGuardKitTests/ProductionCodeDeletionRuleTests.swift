import Testing
@testable import RegressionGuardKit

@Suite("Production code deletion rule tests")
struct ProductionCodeDeletionRuleTests {
  let rule = ProductionCodeDeletionRule()

  @Test("flags force unwrap introduced")
  func flagsForceUnwrapIntroduced() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    guard let value = maybeValue else { return nil }"],
      added: ["    let value = maybeValue!"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.contains { $0.message.contains("Force-unwrap") })
  }

  @Test("flags empty catch block")
  func flagsEmptyCatchBlock() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    } catch { log.error(error) }"],
      added: ["    } catch {}"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.contains { $0.message.contains("Empty") })
  }

  @Test("flags lopsided control flow deletion")
  func flagsLopsidedControlFlowDeletion() async {
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
    #expect(!violations.isEmpty)
  }

  @Test("does not flag genuine refactor")
  func doesNotFlagGenuineRefactor() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: ["    if !isValid { throw ValidationError.invalid }"],
      added: ["    guard isValid else { throw ValidationError.invalid }"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }

  @Test("ignores test files")
  func ignoresTestFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/FooTests.swift",
      removed: ["    guard let value = maybeValue else { return nil }"],
      added: ["    let value = maybeValue!"]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }

  @Test("does not flag boolean negation or not equal")
  func doesNotFlagBooleanNegationOrNotEqual() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Foo.swift",
      removed: [],
      added: [
        "    if !isValid { return }",
        "    guard a != b else { return }",
      ]
    )
    let violations = await rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }
}
