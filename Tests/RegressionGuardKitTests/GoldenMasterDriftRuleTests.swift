import XCTest
@testable import RegressionGuardKit

final class CharacterizationDriftRuleTests: XCTestCase {
  let rule = CharacterizationDriftRule()

  func testFlagsUnapprovedSnapshotChange() {
    let diff = TestSupport.fileDiff(
      path: "Sources/__GoldenMasters__/testRender.snapshot.txt",
      removed: ["<old html>"],
      added: ["<new html>"]
    )
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertEqual(violations.count, 1)
    XCTAssertEqual(violations.first?.severity, .warning)
  }

  func testAllowsApprovedSnapshotChange() {
    let diff = TestSupport.fileDiff(
      path: "Sources/__GoldenMasters__/testRender.snapshot.txt",
      removed: ["<old html>"],
      added: ["<new html>"]
    )
    let context = TestSupport.context(commitMessages: [
      "Update invoice layout\n\nregression-guard:approve"
    ])
    let violations = rule.evaluate(fileDiff: diff, context: context)
    XCTAssertTrue(violations.isEmpty)
  }

  func testIgnoresUnrelatedFiles() {
    let diff = TestSupport.fileDiff(path: "Sources/Foo.swift", removed: ["a"], added: ["b"])
    let violations = rule.evaluate(fileDiff: diff, context: TestSupport.context())
    XCTAssertTrue(violations.isEmpty)
  }
}
