import Foundation

/// Flags changes to recorded characterization snapshots that lack the approval marker.
public struct CharacterizationDriftRule: Rule {
  public static let ruleID = "golden_master_drift"
  public static let defaultSeverity = Severity.warning

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard fileDiff.displayPath.contains("\(CharacterizationPathMarker.directoryName)/") else {
      return []
    }
    guard !context.isApproved else { return [] }
    let settings = Self.settings(from: context)
    let changeKind = fileDiff.isAdded ? "added" : deletionAwareChangeKind(fileDiff)

    return [
      Violation(
        ruleID: Self.ruleID,
        severity: settings.severity,
        file: fileDiff.displayPath,
        message: "Snapshot was \(changeKind) without an approval marker.",
        detail: approvalDetail(context)
      )
    ]
  }

  private func deletionAwareChangeKind(_ fileDiff: FileDiff) -> String {
    fileDiff.isDeleted ? "deleted" : "changed"
  }

  private func approvalDetail(_ context: RuleContext) -> String {
    "Add \"\(context.configuration.approvalMarker)\" to a commit message if intentional."
  }
}

/// Keeps the snapshot directory name in one place without coupling to the snapshot target.
enum CharacterizationPathMarker {
  static let directoryName = "__GoldenMasters__"
}
