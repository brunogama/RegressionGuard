import Foundation

/// An explicit review outcome and optional durable reference for one guard finding.
public struct ReviewAssessment: Codable, Equatable, Sendable {
  public let outcome: ReviewOutcome
  public let reference: String?

  public init(outcome: ReviewOutcome, reference: String? = nil) {
    self.outcome = outcome
    self.reference = reference
  }

  public init(from decoder: any Decoder) throws {
    if let outcome = try? ReviewOutcome(from: decoder) {
      self.init(outcome: outcome)
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let outcome = try container.decode(ReviewOutcome.self, forKey: .outcome)
    let reference = try container.decodeIfPresent(String.self, forKey: .reference)
    self.init(outcome: outcome, reference: reference)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(outcome, forKey: .outcome)
    try container.encodeIfPresent(reference, forKey: .reference)
  }

  private enum CodingKeys: String, CodingKey {
    case outcome
    case reference
  }
}
