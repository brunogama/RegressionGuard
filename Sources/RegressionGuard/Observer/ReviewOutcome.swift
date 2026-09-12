/// A maintainer's explicit assessment of a reported finding.
public enum ReviewOutcome: String, Codable, Equatable, Sendable {
  case confirmed
  case legitimate
  case inconclusive
}
