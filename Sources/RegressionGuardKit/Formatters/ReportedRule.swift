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
  /// `false` when configuration switched this rule off, so it produced no findings by choice.
  ///
  /// A deferred rule is listed rather than omitted. Omitting it would say "this family was never
  /// here", which is the reading the upgrade note's own deferral advice would otherwise create:
  /// a repository that sets `enabled: false` would make the family indistinguishable from one a
  /// older guard never had.
  public let enabled: Bool

  public init(ruleID: String, severity: Severity, blocking: Bool, enabled: Bool = true) {
    self.ruleID = ruleID
    self.severity = severity
    self.blocking = blocking
    self.enabled = enabled
  }

  public init(ruleID: String, severity: Severity, failOn: Severity, enabled: Bool = true) {
    // A rule that did not run cannot have failed the build, whatever its severity says.
    self.init(
      ruleID: ruleID,
      severity: severity,
      blocking: enabled && severity >= failOn,
      enabled: enabled
    )
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ruleID = try container.decode(String.self, forKey: .ruleID)
    severity = try container.decode(Severity.self, forKey: .severity)
    blocking = try container.decode(Bool.self, forKey: .blocking)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
  }
}
