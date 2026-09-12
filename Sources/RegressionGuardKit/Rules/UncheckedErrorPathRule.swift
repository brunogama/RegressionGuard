import Foundation

/// Flags production changes that replace explicit failure handling with unchecked paths.
///
/// The whole of this rule reads source structure, so it all moves to the tree and what is left
/// here is the degradation path. See `UncheckedErrorPathRule+Syntax.swift`.
public struct UncheckedErrorPathRule: SyntaxAwareRule {
  public static let ruleID = "error_handling_collapse"
  public static let defaultSeverity = Severity.warning

  public init() {}

  public func diffViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] { [] }

  public func textFallbackViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard context.isProductionPath(fileDiff) else { return [] }
    let severity = Self.settings(from: context).severity
    return detectForceUnwraps(in: fileDiff, severity: severity)
      + detectSwallowedCatch(in: fileDiff, severity: severity)
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
