import Testing
@testable import RegressionGuardKit

@Suite("Characterization drift rule tests")
struct CharacterizationDriftRuleTests {
  let rule = CharacterizationDriftRule()

  @Test("flags an unapproved snapshot change")
  func flagsUnapprovedSnapshotChange() {
    let diff = TestSupport.fileDiff(
      path: "Sources/__GoldenMasters__/testRender.snapshot.txt",
      removed: ["<old html>"],
      added: ["<new html>"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.count == 1)
    #expect(violations.first?.severity == .warning)
  }

  @Test("allows an approved snapshot change")
  func allowsApprovedSnapshotChange() {
    let diff = TestSupport.fileDiff(
      path: "Sources/__GoldenMasters__/testRender.snapshot.txt",
      removed: ["<old html>"],
      added: ["<new html>"]
    )
    let context = TestSupport.context(commitMessages: [
      "Update invoice layout\n\nregression-guard:approve"
    ])
    let violations = rule.evaluate(fileDiff: diff, context: context)
    #expect(violations.isEmpty)
  }

  @Test("ignores unrelated files")
  func ignoresUnrelatedFiles() {
    let diff = TestSupport.fileDiff(path: "Sources/Foo.swift", removed: ["a"], added: ["b"])
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    #expect(violations.isEmpty)
  }
}
