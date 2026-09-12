import Commander

/// Typed reads out of Commander's parsed values.
///
/// Commander's property wrappers register metadata and nothing else - they never receive the
/// parsed value, and the package ships no binder - so a command has to lift its own options out of
/// `ParsedValues`. This is that lift, in one place, so a missing or malformed option fails the same
/// way for every command instead of once per call site.
///
/// Keys are property labels, because that is what `CommandParser` records; the `--kebab-case`
/// spelling is derived back from the label only for error messages, so the two cannot disagree.
public struct ParsedOptions: Sendable {
  private let values: ParsedValues

  public init(_ values: ParsedValues) {
    self.values = values
  }

  /// The last value given for `label`, or `nil` when the option was not supplied.
  ///
  /// Last rather than first, so repeating an option overrides an earlier one, which is what a
  /// caller building a command line from a script expects.
  public func string(_ label: String) -> String? {
    values.options[label]?.last
  }

  public func string(_ label: String, or fallback: String) -> String {
    string(label) ?? fallback
  }

  /// - Throws: `ValidationError` naming the option when it was not supplied.
  public func required(_ label: String) throws -> String {
    guard let value = string(label) else {
      throw ValidationError("--\(Self.optionName(for: label)) is required")
    }
    return value
  }

  /// - Throws: `ValidationError` naming the option when its value is not a number.
  public func double(_ label: String, or fallback: Double) throws -> Double {
    guard let raw = string(label) else { return fallback }
    guard let value = Double(raw) else {
      throw ValidationError(
        "--\(Self.optionName(for: label)) expects a number, but got '\(raw)'"
      )
    }
    return value
  }

  public func isSet(_ label: String) -> Bool {
    values.flags.contains(label)
  }

  /// Mirrors Commander's own `.automatic` label-to-name conversion, so `reportFile` reads back as
  /// `report-file` in the message a user sees.
  static func optionName(for label: String) -> String {
    var name = ""
    for character in label {
      if character.isUppercase {
        if !name.isEmpty { name.append("-") }
        name.append(Character(character.lowercased()))
      } else {
        name.append(character)
      }
    }
    return name
  }
}
