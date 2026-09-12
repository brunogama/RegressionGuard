import Foundation
import RegressionGuardKit
import Testing

@testable import RegressionGuardObserver

/// An upgrade brings rule IDs the observer has never seen reviewed. None of them may read as a
/// rule with a clean record, because no record and a good record are not the same claim.
@Suite("Uncalibrated rule tests")
struct UncalibratedRuleTests {
  private func report(
    findings: [Violation],
    rules: [ReportedRule] = []
  ) -> GuardReport {
    GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: findings,
      rules: rules
    )
  }

  private func finding(_ ruleID: String) -> Violation {
    Violation(
      ruleID: ruleID,
      severity: .warning,
      file: "Sources/A.swift",
      message: "Function body was replaced by a stub instead of implemented."
    )
  }

  @Test("a rule with findings but no reviews has no false-positive rate, rather than a rate of 0")
  func unreviewedRuleHasNoRate() throws {
    let observation = ReportObserver().observe(report: report(findings: [finding("a_rule")]))
    let calibration = try #require(observation.calibrations.first)

    #expect(calibration.falsePositiveRate == nil)
    #expect(!calibration.hasReviewHistory)
    #expect(!calibration.meetsReviewThreshold)
  }

  @Test("a rule that ran and found nothing is still calibrated, so silence is visible")
  func ruleThatFoundNothingIsStillListed() {
    let observation = ReportObserver().observe(
      report: report(
        findings: [],
        rules: [
          ReportedRule(ruleID: "implementation_stubbed", severity: .warning, blocking: false)
        ]
      )
    )

    #expect(observation.calibrations.map(\.ruleID) == ["implementation_stubbed"])
    #expect(observation.calibrations.first?.findingCount == 0)
    #expect(observation.calibrations.first?.hasReviewHistory == false)
  }

  @Test("a reviewed rule reports a rate and a history")
  func reviewedRuleHasHistory() throws {
    let violation = finding("a_rule")
    let report = report(findings: [violation])
    let id = try #require(report.findings.first?.id)
    let observation = ReportObserver().observe(report: report, outcomes: [id: .legitimate])
    let calibration = try #require(observation.calibrations.first)

    #expect(calibration.hasReviewHistory)
    #expect(calibration.falsePositiveRate == 1.0)
  }

  @Test("a rule that ran and one that fired both appear exactly once")
  func rulesAreNotDuplicated() {
    let observation = ReportObserver().observe(
      report: report(
        findings: [finding("implementation_stubbed")],
        rules: [
          ReportedRule(ruleID: "implementation_stubbed", severity: .warning, blocking: false),
          ReportedRule(ruleID: "weakened_assertion", severity: .error, blocking: true),
        ]
      )
    )

    let ruleIDs = observation.calibrations.map(\.ruleID)
    #expect(ruleIDs == ["implementation_stubbed", "weakened_assertion"])
    #expect(observation.calibrations.first?.findingCount == 1)
  }
}
