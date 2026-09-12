/// Per-rule review and false-positive calibration derived from observer evidence.
public struct RuleCalibration: Codable, Equatable, Sendable {
  public static let reviewThreshold = 20

  public let ruleID: String
  public let findingCount: Int
  public let reviewedFindingCount: Int
  public let confirmedCount: Int
  public let legitimateCount: Int
  public let inconclusiveCount: Int
  public let falsePositiveRate: Double?

  public var meetsReviewThreshold: Bool {
    reviewedFindingCount >= Self.reviewThreshold
  }

  /// `true` when a human has judged at least one of this rule's findings.
  ///
  /// The distinction an upgrade makes load-bearing. A rule family a repository has just acquired
  /// has no reviews, and `falsePositiveRate == nil` alone is ambiguous between "nobody has looked"
  /// and "nothing to compute a rate from". A reader promoting a rule to blocking needs to know
  /// which, and absence of evidence must never be presented as evidence of accuracy.
  public var hasReviewHistory: Bool { reviewedFindingCount > 0 }

  public init(ruleID: String, findings: [ObservedFinding]) {
    self.ruleID = ruleID
    findingCount = findings.count
    confirmedCount = findings.filter { $0.reviewOutcome == .confirmed }.count
    legitimateCount = findings.filter { $0.reviewOutcome == .legitimate }.count
    inconclusiveCount = findings.filter { $0.reviewOutcome == .inconclusive }.count
    reviewedFindingCount = confirmedCount + legitimateCount + inconclusiveCount
    let rateDenominator = confirmedCount + legitimateCount
    falsePositiveRate =
      rateDenominator == 0
      ? nil
      : Double(legitimateCount) / Double(rateDenominator)
  }
}
