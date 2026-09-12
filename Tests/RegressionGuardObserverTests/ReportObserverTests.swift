import Foundation
import Testing
@testable import RegressionGuardKit
@testable import RegressionGuardObserver

@Suite("Report observer tests")
struct ReportObserverTests {
  @Test("preserves stable finding evidence until an outcome is recorded")
  func preservesStableFindingEvidence() {
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: [
        Violation(
          ruleID: "weakened_assertion",
          severity: .error,
          file: "Tests/ExampleTests.swift",
          line: 12,
          message: "Assertion was removed."
        )
      ]
    )

    let observation = ReportObserver().observe(report: report)

    #expect(observation.schemaVersion == 1)
    #expect(observation.runID == "HEAD")
    #expect(observation.findings.count == 1)
    #expect(observation.findings[0].findingID == report.findings[0].id)
    #expect(observation.findings[0].reviewOutcome == nil)
    #expect(observation.findings[0].file == "Tests/ExampleTests.swift")
    #expect(observation.findings[0].line == 12)
    #expect(observation.findings[0].message == "Assertion was removed.")
    #expect(observation.findings[0].detail == nil)
    #expect(observation.findings[0].confidence == "unclassified")
    #expect(observation.findings[0].evidenceReferences.isEmpty)
    #expect(!observation.findings[0].approved)
    #expect(observation.findings[0].remediation != nil)
  }
  @Test("summarizes reviewed findings by rule")
  func summarizesReviewedFindingsByRule() throws {
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: (1...4).map { index in
        Violation(
          ruleID: "weakened_assertion",
          severity: .error,
          file: "Tests/ExampleTests.swift",
          line: index,
          message: "Assertion was removed."
        )
      }
    )
    let outcomes = [
      report.findings[0].id: ReviewOutcome.confirmed,
      report.findings[1].id: ReviewOutcome.legitimate,
      report.findings[2].id: ReviewOutcome.inconclusive,
    ]
    let observation = ReportObserver().observe(report: report, outcomes: outcomes)
    let calibration = try #require(observation.calibrations.first)

    #expect(calibration.ruleID == "weakened_assertion")
    #expect(calibration.findingCount == 4)
    #expect(calibration.reviewedFindingCount == 3)
    #expect(calibration.falsePositiveRate == 0.5)
    #expect(!calibration.meetsReviewThreshold)

    let unreviewed = RuleCalibration(
      ruleID: "weakened_assertion",
      findings: Array(repeating: observation.findings[3], count: 20)
    )
    #expect(unreviewed.falsePositiveRate == nil)
    #expect(!unreviewed.meetsReviewThreshold)
  }

  @Test("qualifies after twenty reviewed findings")
  func qualifiesAfterTwentyReviewedFindings() {
    let guardFinding = GuardFinding(
      violation: Violation(
        ruleID: "weakened_assertion",
        severity: .error,
        file: "Tests/ExampleTests.swift",
        line: 1,
        message: "Assertion was removed."
      )
    )
    let finding = ObservedFinding(
      finding: guardFinding,
      reviewOutcome: .confirmed
    )
    let calibration = RuleCalibration(
      ruleID: "weakened_assertion",
      findings: Array(repeating: finding, count: RuleCalibration.reviewThreshold)
    )

    #expect(calibration.meetsReviewThreshold)
  }


  @Test("retains repository and review reference with the finding")
  func retainsRepositoryAndReviewReference() {
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: "example/RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: [
        Violation(
          ruleID: "weakened_assertion",
          severity: .error,
          file: "Tests/ExampleTests.swift",
          message: "Assertion was removed."
        )
      ]
    )
    let findingID = report.findings[0].id
    let assessments = [
      findingID: ReviewAssessment(
        outcome: .legitimate,
        reference: "https://example.test/reviews/42"
      )
    ]
    let observation = ReportObserver().observe(report: report, assessments: assessments)
    let finding = observation.findings[0]

    #expect(observation.repository == "example/RegressionGuard")
    #expect(finding.reviewOutcome == .legitimate)
    #expect(finding.reviewReference == "https://example.test/reviews/42")
  }

  @Test("encodes a versioned observer artifact")
  func encodesVersionedObservation() throws {
    let observation = ReportObservation(runID: "HEAD", findings: [])
    let data = try ObservationJSONFormatter().data(for: observation)
    let decoded = try JSONDecoder().decode(ReportObservation.self, from: data)

    #expect(decoded == observation)
  }
}
