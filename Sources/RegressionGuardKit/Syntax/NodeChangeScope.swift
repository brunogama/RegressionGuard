import Foundation

/// Where a change falls relative to one syntax node.
///
/// A node's span covers every line it occupies, most of which a change never touched. Knowing
/// only that a change landed somewhere inside a node is not enough: a rule that treats a body
/// edit as a change to the enclosing declaration reports findings against code the author never
/// wrote, which is the fastest way to lose trust in the tool.
public enum NodeChangeScope: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  /// No changed line falls inside the node. It is in the file, but not in the change.
  case outside
  /// A changed line falls on the node's own lines, such as a declaration's signature.
  case own
  /// Changed lines fall only inside the node's children, such as a body edited under a signature
  /// the change never touched.
  case nested

  /// `true` when the change reached this node at all, whether on its own lines or below them.
  public var isChanged: Bool { self != .outside }
}
