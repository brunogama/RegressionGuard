import Foundation

/// Flags lopsided removal of production control-flow or validation logic.
///
/// The whole of this rule reads source structure, so it all moves to the tree and what is left
/// here is the degradation path. See `ControlFlowDeletionRule+Syntax.swift`.
public struct ControlFlowDeletionRule: SyntaxAwareRule {
  public static let ruleID = "behavior_deletion"
  public static let defaultSeverity = Severity.warning

  /// How much control flow has to disappear before the removal reads as a shortcut rather than
  /// ordinary simplification.
  ///
  /// Shared by both paths so the tree and the text agree on the bar.
  static let removalThreshold = 3

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

  public func diffViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] { [] }

  public func textFallbackViolations(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard context.isProductionPath(fileDiff) else { return [] }
    let removed = Self.controlFlowLines(in: fileDiff.removedLines)
    let added = Self.controlFlowLines(in: fileDiff.addedLines)
    guard removed.count >= Self.removalThreshold, added.isEmpty else { return [] }

    return [
      Violation(
        ruleID: Self.ruleID,
        severity: Self.settings(from: context).severity,
        file: fileDiff.displayPath,
        line: removed.first?.number,
        message: "\(removed.count) control-flow line(s) removed without replacement.",
        detail: removed.prefix(5)
          .map { $0.text.trimmingCharacters(in: .whitespaces) }
          .joined(separator: "\n")
      )
    ]
  }

  private static func controlFlowLines(in lines: [DiffLine]) -> [DiffLine] {
    lines.filter { line in
      Self.controlFlowKeywords.contains { line.text.contains($0) }
    }
  }
}
