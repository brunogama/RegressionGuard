import Foundation

/// What a finding was judged on.
///
/// A rule that reads parsed syntax keeps its line-based detection as the degradation path, so the
/// same rule ID can reach the same conclusion from two different kinds of evidence with two
/// different precisions. A reader - and the observer calibrating the rule - has to be able to tell
/// them apart, because a degraded finding is the weaker claim and the findings a degraded run
/// never made are invisible by construction.
public enum ViolationEvidence: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  /// The diff itself: its added and removed lines, or the file metadata around them. The evidence
  /// for detections that gain nothing from a tree, such as a deleted test file.
  case diff
  /// Parsed base and head syntax trees, read through the change.
  case syntax
  /// A syntax-backed detection that ran on diff text because a tree was unavailable. The finding
  /// stands at the precision of the text matcher, and the run reports the gap that caused it.
  case degradedDiff

  /// `true` when this finding was reached without the tree its rule asked for.
  public var isDegraded: Bool { self == .degradedDiff }
}
