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
    // Every rule the run reports having enabled gets a calibration, not only the ones that fired.
    // A family that ran and found nothing leaves no findings to group, so grouping alone would
    // drop it from the artifact entirely - and an absent rule reads like a rule that was never
    // there, which is exactly the reading an upgrade makes dangerous.
    let findingsByRule = Dictionary(grouping: findings, by: \.ruleID)
    let ruleIDs = Set(findingsByRule.keys).union(report.rules.map(\.ruleID))
    let calibrations = ruleIDs
      .map { RuleCalibration(ruleID: $0, findings: findingsByRule[$0] ?? []) }
      .sorted { $0.ruleID < $1.ruleID }
    return ReportObservation(
      runID: report.runID,
      repository: report.repository,
      findings: findings,
      calibrations: calibrations
    )
  }
}
