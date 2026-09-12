import Foundation

/// Anything that can be turned into a stable, comparable text representation for snapshot
/// recording. Conform your own types instead of relying on `String(describing:)`, which is
/// not guaranteed to be stable across Swift versions.
public protocol CharacterizationSnapshottable {
  func characterizationSnapshot() -> String
}

extension String: CharacterizationSnapshottable {
  public func characterizationSnapshot() -> String { self }
}

extension Data: CharacterizationSnapshottable {
  public func characterizationSnapshot() -> String {
    base64EncodedString()
  }
}

/// Default snapshot for any `Encodable` value: stable, sorted-key, pretty-printed JSON.
public extension Encodable {
  func characterizationJSONSnapshot() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self),
      let string = String(data: data, encoding: .utf8)
    else {
      return "<<unencodable \(type(of: self))>>"
    }
    return string
  }
}

/// Wraps any `Encodable` value so it can be passed to `Characterization.verify` without each
/// call site needing to conform the type itself.
public struct AnyEncodableSnapshot: CharacterizationSnapshottable {
  private let snapshot: String
  public init<T: Encodable>(_ value: T) {
    self.snapshot = value.characterizationJSONSnapshot()
  }
  public func characterizationSnapshot() -> String { snapshot }
}
