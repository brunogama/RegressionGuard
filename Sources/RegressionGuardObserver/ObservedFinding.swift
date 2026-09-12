import RegressionGuardKit

/// One guard finding retained as observer evidence with an optional review outcome.
public struct ObservedFinding: Codable, Equatable, Sendable {
  public let findingID: String
  public let ruleID: String
  public let severity: Severity
  public let file: String
  public let line: Int?
  public let message: String
  public let detail: String?
  public let confidence: String
  public let evidenceReferences: [String]
  public let approved: Bool
  public let remediation: String?
  public let reviewOutcome: ReviewOutcome?
  public let reviewReference: String?

  public init(
    finding: GuardFinding,
    reviewOutcome: ReviewOutcome?,
    reviewReference: String? = nil
  ) {
    self.findingID = finding.id
    self.ruleID = finding.ruleID
    self.severity = finding.severity
    self.file = finding.file
    self.line = finding.line
    self.message = finding.message
    self.detail = finding.detail
    self.confidence = finding.confidence
    self.evidenceReferences = finding.evidenceReferences
    self.approved = finding.approved
    self.remediation = finding.remediation
    self.reviewOutcome = reviewOutcome
    self.reviewReference = reviewReference
  }
}
