import Foundation

/// Compatibility facade for the split production shortcut rules.
public struct ProductionCodeDeletionRule: Rule {
  public static let ruleID = "production_code_deletion"
  public static let defaultSeverity = Severity.warning

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    let severity = Self.settings(from: context).severity
    return
      (ControlFlowDeletionRule().evaluate(fileDiff: fileDiff, context: context)
      + UncheckedErrorPathRule().evaluate(fileDiff: fileDiff, context: context)).map { finding in
        var finding = finding
        finding.severity = severity
        return finding
      }
  }
}

/// Flags lopsided removal of production control-flow or validation logic.
public struct ControlFlowDeletionRule: Rule {
  public static let ruleID = "behavior_deletion"
  public static let defaultSeverity = Severity.warning

  private static let controlFlowKeywords = [
    "if ",
    "guard ",
    "for ",
    "while ",
    "switch ",
    "throw ",
    "catch",
    "return",
  ]

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard isProduction(fileDiff, context: context) else { return [] }
    let removed = Self.controlFlowLines(in: fileDiff.removedLines)
    let added = Self.controlFlowLines(in: fileDiff.addedLines)
    guard removed.count >= 3, added.isEmpty else { return [] }

    let severity = Self.settings(from: context).severity
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: fileDiff.displayPath,
        line: removed.first?.number,
        message: "\(removed.count) control-flow line(s) removed without replacement.",
        detail: removed.prefix(5)
          .map { $0.text.trimmingCharacters(in: .whitespaces) }
          .joined(separator: "\n")
      )
    ]
  }

  private func isProduction(_ fileDiff: FileDiff, context: RuleContext) -> Bool {
    !context.pathClassifier.isTestPath(fileDiff.displayPath)
      && !context.pathClassifier.isIgnored(fileDiff.displayPath)
  }

  private static func controlFlowLines(in lines: [DiffLine]) -> [DiffLine] {
    lines.filter { line in
      Self.controlFlowKeywords.contains { line.text.contains($0) }
    }
  }
}

/// Flags production changes that replace explicit failure handling with unchecked paths.
public struct UncheckedErrorPathRule: Rule {
  public static let ruleID = "error_handling_collapse"
  public static let defaultSeverity = Severity.warning

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard isProduction(fileDiff, context: context) else { return [] }
    let severity = Self.settings(from: context).severity
    return detectForceUnwraps(in: fileDiff, severity: severity)
      + detectSwallowedCatch(in: fileDiff, severity: severity)
  }

  private func isProduction(_ fileDiff: FileDiff, context: RuleContext) -> Bool {
    !context.pathClassifier.isTestPath(fileDiff.displayPath)
      && !context.pathClassifier.isIgnored(fileDiff.displayPath)
  }

  private func detectForceUnwraps(in fileDiff: FileDiff, severity: Severity) -> [Violation] {
    fileDiff.addedLines.compactMap { added in
      guard Self.looksLikeForceUnwrap(added.text) else { return nil }
      return Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: fileDiff.displayPath,
        line: added.number,
        message: "Force-unwrap introduced instead of proper error/optional handling.",
        detail: added.text.trimmingCharacters(in: .whitespaces)
      )
    }
  }

  private static func looksLikeForceUnwrap(_ text: String) -> Bool {
    guard text.contains("!") else { return false }
    let stripped = text.replacingOccurrences(of: "!=", with: "")
    guard stripped.contains("!") else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("!") { return false }
    if trimmed.contains(": ") && trimmed.hasSuffix("!") { return false }
    return stripped.range(of: #"[A-Za-z0-9_\)\]]\!"#, options: .regularExpression) != nil
  }

  private func detectSwallowedCatch(in fileDiff: FileDiff, severity: Severity) -> [Violation] {
    let added = fileDiff.addedLines.map(\.text).joined(separator: "\n")
    guard added.range(of: #"catch[^\{]*\{\s*\}"#, options: .regularExpression) != nil else {
      return []
    }
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: severity,
        file: fileDiff.displayPath,
        message: "Empty `catch` block introduced - the error is now silently discarded.",
        detail: nil
      )
    ]
  }
}
