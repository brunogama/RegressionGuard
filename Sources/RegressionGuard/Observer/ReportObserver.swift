import RegressionGuardKit

/// Creates deterministic observer artifacts from versioned guard reports.
public struct ReportObserver {
  public init() {}

  public func observe(
    report: GuardReport,
    outcomes: [String: ReviewOutcome] = [:]
  ) -> ReportObservation {
    let assessments = outcomes.mapValues { ReviewAssessment(outcome: $0) }
    return observe(report: report, assessments: assessments)
  }

  public func observe(
    report: GuardReport,
    assessments: [String: ReviewAssessment]
  ) -> ReportObservation {
    let findings = report.findings.map { finding in
      let assessment = assessments[finding.id]
      return ObservedFinding(
        finding: finding,
        reviewOutcome: assessment?.outcome,
        reviewReference: assessment?.reference
      )
    }
    let calibrations = Dictionary(grouping: findings, by: \.ruleID)
      .map { RuleCalibration(ruleID: $0.key, findings: $0.value) }
      .sorted { $0.ruleID < $1.ruleID }
    return ReportObservation(
      runID: report.runID,
      repository: report.repository,
      findings: findings,
      calibrations: calibrations
    )
  }
}
