import Foundation

public extension SyntaxNode {
  /// Nodes at or below this one that declare or reference `name`.
  func nodes(named name: String) -> [Self] {
    selfAndDescendants.filter { $0.name == name }
  }

  /// - Returns: `true` when this node or anything below it carries one of `kinds`.
  func containsNode(ofAnyKind kinds: Set<SyntaxNodeKind>) -> Bool {
    selfAndDescendants.contains { kinds.contains($0.kind) }
  }

  /// Nodes at or below this one whose kind is any of `kinds`, depth first in source order.
  func nodes(ofAnyKind kinds: Set<SyntaxNodeKind>) -> [Self] {
    selfAndDescendants.filter { kinds.contains($0.kind) }
  }

  /// The smallest node of `kind` whose span encloses `span`.
  ///
  /// Used to name the declaration a finding sits in, so a report says which test was disabled
  /// rather than only which line changed.
  func innermostNode(ofKind kind: SyntaxNodeKind, containing span: LineSpan) -> Self? {
    nodes(ofKind: kind)
      .filter { $0.span.contains(span) }
      .min { lhs, rhs in lhs.span.lineNumbers.count < rhs.span.lineNumbers.count }
  }
}

public extension SyntaxTree {
  /// Nodes whose kind is any of `kinds`, depth first in source order.
  func nodes(ofAnyKind kinds: Set<SyntaxNodeKind>) -> [SyntaxNode] {
    root.nodes(ofAnyKind: kinds)
  }

  /// The smallest node of `kind` whose span encloses `span`.
  func innermostNode(ofKind kind: SyntaxNodeKind, containing span: LineSpan) -> SyntaxNode? {
    root.innermostNode(ofKind: kind, containing: span)
  }
}
