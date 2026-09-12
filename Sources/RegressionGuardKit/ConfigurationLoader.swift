import Foundation

/// Loads `.regressionguard.yml` / `.regressionguard.yaml` / `.regressionguard.json` from a
/// directory, falling back to `Configuration.default` when none exists.
///
/// The YAML support is a small, purpose-built reader for this tool's own config schema. It is
/// dependency-free by design. If you hit its limits, use `.regressionguard.json` instead.
public struct ConfigurationLoader {
  public init() {}

  public static let defaultFileNames = [
    ".regressionguard.yml",
    ".regressionguard.yaml",
    ".regressionguard.json",
  ]

  public func load(fromDirectory directory: URL) -> Configuration {
    for name in Self.defaultFileNames {
      let url = directory.appendingPathComponent(name)
      guard let data = try? Data(contentsOf: url) else { continue }
      if let config = Self.decode(data, named: name) {
        return config
      }
    }
    return .default
  }

  // MARK: - Minimal YAML reader

  static func parseYAML(_ text: String) -> Configuration? {
    var accumulator = YamlConfigurationAccumulator()

    for rawLine in text.components(separatedBy: "\n") {
      guard let line = YamlLine(rawLine) else { continue }
      accumulator.consume(line)
    }

    return accumulator.configuration
  }

  private static func decode(_ data: Data, named name: String) -> Configuration? {
    if name.hasSuffix(".json") {
      return try? JSONDecoder().decode(Configuration.self, from: data)
    }
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    return Self.parseYAML(text)
  }

  fileprivate static func stripComment(_ line: String) -> String {
    guard let hashIndex = line.firstIndex(of: "#") else { return line }
    return String(line[line.startIndex..<hashIndex])
  }

  fileprivate static func scalarValue(after prefix: String, in line: String) -> String? {
    guard let range = line.range(of: prefix) else { return nil }
    let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? nil : unquote(value)
  }

  fileprivate static func unquote(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    if isQuoted(value, quote: "\"") || isQuoted(value, quote: "'") {
      return String(value.dropFirst().dropLast())
    }
    return value
  }

  private static func isQuoted(_ value: String, quote: Character) -> Bool {
    value.first == quote && value.last == quote
  }
}

private enum YamlSection {
  case none
  case rules
  case ignore
  case testPaths
}

private struct YamlLine {
  let indent: Int
  let trimmed: String

  init?(_ rawLine: String) {
    let noComment = ConfigurationLoader.stripComment(rawLine)
    let trimmed = noComment.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    self.indent = noComment.prefix(while: { $0 == " " }).count
    self.trimmed = trimmed
  }
}

private struct YamlRuleAccumulator {
  var headerIndent: Int?
  var id: String?
  var enabled = true
  var severity = Severity.error
  var options: [String: String] = [:]

  mutating func flush(into rules: inout [String: RuleSettings]) {
    guard let id else { return }
    rules[id] = RuleSettings(enabled: enabled, severity: severity, options: options)
    self.id = nil
    enabled = true
    severity = .error
    options = [:]
  }
}

private struct YamlConfigurationAccumulator {
  private var rules: [String: RuleSettings] = [:]
  private var ignore: [String] = []
  private var testPaths: [String] = []
  private var approvalMarker = Configuration.default.approvalMarker
  private var section = YamlSection.none
  private var rule = YamlRuleAccumulator()

  var configuration: Configuration? {
    var mutableRule = rule
    var mutableRules = rules
    mutableRule.flush(into: &mutableRules)
    guard !mutableRules.isEmpty || !ignore.isEmpty || !testPaths.isEmpty else { return nil }
    var config = Configuration.default
    if !mutableRules.isEmpty { config.rules = mutableRules }
    if !ignore.isEmpty { config.ignore = ignore }
    if !testPaths.isEmpty { config.testPaths = testPaths }
    config.approvalMarker = approvalMarker
    return config
  }

  mutating func consume(_ line: YamlLine) {
    if line.indent == 0 {
      consumeRoot(line.trimmed)
      return
    }

    switch section {
    case .rules: consumeRule(line)
    case .ignore: appendListItem(line.trimmed, to: &ignore)
    case .testPaths: appendListItem(line.trimmed, to: &testPaths)
    case .none: break
    }
  }

  private mutating func consumeRoot(_ trimmed: String) {
    rule.flush(into: &rules)
    rule.headerIndent = nil
    section = rootSection(for: trimmed)
    if trimmed.hasPrefix("approvalMarker:") {
      approvalMarker =
        ConfigurationLoader.scalarValue(
          after: "approvalMarker:",
          in: trimmed
        ) ?? approvalMarker
    }
  }

  private func rootSection(for trimmed: String) -> YamlSection {
    if trimmed == "rules:" { return .rules }
    if trimmed == "ignore:" { return .ignore }
    if trimmed == "testPaths:" { return .testPaths }
    return .none
  }

  private mutating func consumeRule(_ line: YamlLine) {
    if isRuleHeader(line) {
      rule.flush(into: &rules)
      rule.headerIndent = line.indent
      rule.id = String(line.trimmed.dropLast())
    } else if line.trimmed.hasPrefix("enabled:") {
      rule.enabled = boolValue(line.trimmed, prefix: "enabled:")
    } else if line.trimmed.hasPrefix("severity:") {
      rule.severity = severityValue(line.trimmed)
    } else {
      consumeRuleOption(line.trimmed)
    }
  }

  private func isRuleHeader(_ line: YamlLine) -> Bool {
    guard line.trimmed.hasSuffix(":"), !line.trimmed.hasPrefix("options") else { return false }
    guard !line.trimmed.contains(" ") else { return false }
    guard let headerIndent = rule.headerIndent else { return true }
    return line.indent <= headerIndent
  }

  private func boolValue(_ trimmed: String, prefix: String) -> Bool {
    let value = ConfigurationLoader.scalarValue(after: prefix, in: trimmed) ?? "true"
    return ["true", "yes", "1"].contains(value.lowercased())
  }

  private func severityValue(_ trimmed: String) -> Severity {
    let value = ConfigurationLoader.scalarValue(after: "severity:", in: trimmed) ?? "error"
    return Severity(rawValue: value.lowercased()) ?? .error
  }

  private mutating func consumeRuleOption(_ trimmed: String) {
    let parts = trimmed.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return }
    let key = parts[0].trimmingCharacters(in: .whitespaces)
    let value = parts[1].trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else { return }
    rule.options[key] = ConfigurationLoader.unquote(value)
  }

  private func appendListItem(_ trimmed: String, to values: inout [String]) {
    guard trimmed.hasPrefix("- ") else { return }
    values.append(ConfigurationLoader.unquote(String(trimmed.dropFirst(2))))
  }
}
