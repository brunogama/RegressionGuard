import Foundation

/// Encodes observer artifacts with deterministic JSON key ordering.
public struct ObservationJSONFormatter {
  public init() {}

  public func data(for observation: ReportObservation) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(observation)
  }
}
