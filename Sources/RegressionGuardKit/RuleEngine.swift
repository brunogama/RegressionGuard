import Foundation

/// Runs every enabled rule over the unified evidence bundle.
public struct RuleEngine {
  public let rules: [Rule]

  public init(rules: [Rule] = Self.defaultRules) {
    self.rules = rules
  }

  public static var defaultRules: [Rule] {
    [
      DisabledOrSkippedTestRule(),
      WeakenedAssertionRule(),
      ControlFlowDeletionRule(),
      UncheckedErrorPathRule(),
      GuardConfigurationWeakeningRule(),
      ReviewEscapeRule(),
      CoverageRegressionRule(),
      CharacterizationDriftRule(),
    ]
  }

  /// Compatibility entry point for callers that only have parsed file diffs.
  public func run(diff: [FileDiff], context: RuleContext) -> [Violation] {
    let evidence = EvidenceBundle(
      fileDiffs: diff,
      commit: CommitEvidence(
        baseRef: context.baseRef,
        headRef: context.headRef,
        messages: context.commitMessages
      )
    )
    return run(evidence: evidence, context: context)
  }

  /// Evaluates every enabled rule against one canonical evidence bundle.
  public func run(evidence: EvidenceBundle, context: RuleContext) -> [Violation] {
    let visibleEvidence = excludingIgnoredPaths(from: evidence, context: context)
    var violations: [Violation] = []

    for rule in rules {
      let ruleType = type(of: rule)
      let defaultSettings = RuleSettings(
        enabled: true,
        severity: ruleType.defaultSeverity
      )
      let settings = configuredSettings(
        for: ruleType.ruleID,
        default: defaultSettings,
        context: context
      )
      guard settings.enabled else { continue }
      let evidenceForRule = ruleType.inspectsIgnoredPaths ? evidence : visibleEvidence
      var findings = rule.evaluate(evidence: evidenceForRule, context: context)
      for index in findings.indices {
        findings[index].severity = settings.severity
      }
      violations.append(contentsOf: findings)
    }

    return violations
  }

  private func configuredSettings(
    for ruleID: String,
    default defaultSettings: RuleSettings,
    context: RuleContext
  ) -> RuleSettings {
    if let settings = context.configuration.rules[ruleID] {
      return settings
    }
    let splitRuleIDs = ["behavior_deletion", "error_handling_collapse"]
    guard splitRuleIDs.contains(ruleID) else { return defaultSettings }
    return context.configuration.rules["production_code_deletion"] ?? defaultSettings
  }

  private func excludingIgnoredPaths(
    from evidence: EvidenceBundle,
    context: RuleContext
  ) -> EvidenceBundle {
    let visibleDiffs = evidence.fileDiffs.filter {
      !context.pathClassifier.isIgnored($0.displayPath)
    }
    let visiblePaths = Set(visibleDiffs.map(\.displayPath))
    let visibleContents = evidence.fileContents.filter { visiblePaths.contains($0.key) }
    let visiblePathEvidence = evidence.pathEvidence.filter { visiblePaths.contains($0.key) }
    return EvidenceBundle(
      fileDiffs: visibleDiffs,
      fileContents: visibleContents,
      pathEvidence: visiblePathEvidence,
      commit: evidence.commit,
      repository: evidence.repository
    )
  }
}

/// Flags concrete changes that disable or remove the configured change-validation surface.
public struct GuardConfigurationWeakeningRule: Rule {
  public static let ruleID = "enforcement_weakening"
  public static let defaultSeverity = Severity.error

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard let message = Self.message(for: fileDiff) else { return [] }
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: Self.settings(from: context).severity,
        file: fileDiff.displayPath,
        message: message,
        detail: Self.changedLines(in: fileDiff)
      )
    ]
  }

  private static func message(for fileDiff: FileDiff) -> String? {
    let path = fileDiff.displayPath
    if isRegressionGuardConfiguration(path), disablesRule(in: fileDiff) {
      return "RegressionGuard rule configuration was disabled."
    }
    if isWorkflow(path), removesTestCommand(in: fileDiff) {
      return "CI test command was removed without a replacement."
    }
    if isSwiftLintConfiguration(path), disablesSwiftLintRule(in: fileDiff) {
      return "SwiftLint disabled-rules configuration was added."
    }
    if path == "Package.swift", removesTestTarget(in: fileDiff) {
      return "SwiftPM test target was removed without a replacement."
    }
    return nil
  }

  private static func isRegressionGuardConfiguration(_ path: String) -> Bool {
    [".regressionguard.yml", ".regressionguard.yaml", ".regressionguard.json"].contains(path)
  }

  private static func isWorkflow(_ path: String) -> Bool {
    path.hasPrefix(".github/workflows/") && path.hasSuffix(".yml")
      || path.hasPrefix(".github/workflows/") && path.hasSuffix(".yaml")
  }

  private static func isSwiftLintConfiguration(_ path: String) -> Bool {
    path == ".swiftlint.yml" || path == ".swiftlint.yaml"
  }

  private static func disablesRule(in fileDiff: FileDiff) -> Bool {
    fileDiff.addedLines.contains { line in
      let text = line.text.lowercased().replacingOccurrences(of: " ", with: "")
      return text == "enabled:false" || text == "\"enabled\":false"
    }
  }

  private static func removesTestCommand(in fileDiff: FileDiff) -> Bool {
    let removedTestCommand = fileDiff.removedLines.contains { isTestCommand($0.text) }
    let addedTestCommand = fileDiff.addedLines.contains { isTestCommand($0.text) }
    return removedTestCommand && !addedTestCommand
  }

  private static func isTestCommand(_ text: String) -> Bool {
    text.contains("swift test") || text.contains("xcodebuild test")
  }

  private static func disablesSwiftLintRule(in fileDiff: FileDiff) -> Bool {
    fileDiff.addedLines.contains { line in
      line.text.trimmingCharacters(in: .whitespaces) == "disabled_rules:"
    }
  }

  private static func removesTestTarget(in fileDiff: FileDiff) -> Bool {
    let removedTarget = fileDiff.removedLines.contains { $0.text.contains(".testTarget(") }
    let addedTarget = fileDiff.addedLines.contains { $0.text.contains(".testTarget(") }
    return removedTarget && !addedTarget
  }

  private static func changedLines(in fileDiff: FileDiff) -> String {
    (fileDiff.removedLines + fileDiff.addedLines)
      .prefix(5)
      .map { $0.text.trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
  }
}
