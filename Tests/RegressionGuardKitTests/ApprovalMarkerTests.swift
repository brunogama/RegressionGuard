import Testing
@testable import RegressionGuardKit

@Suite("Approval marker tests")
struct ApprovalMarkerTests {
  @Test("suppresses findings only with an explicit approval marker")
  func suppressesFindingsWithApprovalMarker() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/ExampleTests.swift",
      added: ["  throw XCTSkip(\"intentionally disabled\")"]
    )
    let context = TestSupport.context(
      commitMessages: ["chore: intentional change\n\nregression-guard:approve bootstrap"]
    )

    let findings = await RuleEngine().run(diff: [diff], context: context)

    #expect(findings.isEmpty)
  }
}
