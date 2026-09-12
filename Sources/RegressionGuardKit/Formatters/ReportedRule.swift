import Foundation

/// One rule that ran, and whether it could have failed the build.
///
/// Recorded because an absent rule ID and a silent one are indistinguishable otherwise. A
/// repository upgrading to a syntax-aware guard gains rule families its configuration has never
/// mentioned; without this, "no findings from `implementation_stubbed`" could mean the family
/// found nothing, or that this build ran a version that never had it. The observer needs the
/// difference to calibrate, and a maintainer needs it to trust a clean report.
///
/// `blocking` is derived from the run's own threshold rather than restated by hand, so a report
/// cannot claim a family is advisory while the run was configured to fail on it.
public struct ReportedRule: Codable, Equatable, Sendable {
  public let ruleID: String
  public let severity: Severity
  /// `true` when a finding from this rule would fail the run at its configured threshold.
  public let blocking: Bool

  public init(ruleID: String, severity: Severity, blocking: Bool) {
    self.ruleID = ruleID
    self.severity = severity
    self.blocking = blocking
  }

  public init(ruleID: String, severity: Severity, failOn: Severity) {
    self.init(ruleID: ruleID, severity: severity, blocking: severity >= failOn)
  }
}
