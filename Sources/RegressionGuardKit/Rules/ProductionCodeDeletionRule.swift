import Foundation

/// Compatibility facade for the split production shortcut rules.
public struct ProductionCodeDeletionRule: Rule {
  public static let ruleID = "production_code_deletion"
  public static let defaultSeverity = Severity.warning
  /// Both rules behind this facade read parsed syntax, so the facade has to declare the need on
  /// their behalf - a caller that runs only the facade would otherwise be handed no trees and
  /// silently get the degraded answer.
  public static let requiresSyntacticEvidence = true

  public init() {}

  /// The rules this facade stands in front of.
  private static var split: [any Rule] { [ControlFlowDeletionRule(), UncheckedErrorPathRule()] }

  public func evaluate(evidence: EvidenceBundle, context: RuleContext) async -> [Violation] {
    await reported(context: context) { await $0.evaluate(evidence: evidence, context: context) }
  }

  public func evaluate(fileDiff: FileDiff, context: RuleContext) async -> [Violation] {
    await reported(context: context) { await $0.evaluate(fileDiff: fileDiff, context: context) }
  }

  /// Runs both rules and reports whatever they found under this facade's configured severity.
  private func reported(
    context: RuleContext,
    _ evaluate: (any Rule) async -> [Violation]
  ) async -> [Violation] {
    let severity = Self.settings(from: context).severity
    var findings: [Violation] = []
    for rule in Self.split {
      findings += await evaluate(rule).map { finding in
        var finding = finding
        finding.severity = severity
        return finding
      }
    }
    return findings
  }
}
