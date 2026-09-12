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
