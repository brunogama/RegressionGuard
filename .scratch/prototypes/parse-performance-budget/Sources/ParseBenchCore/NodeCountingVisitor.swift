import SwiftSyntax

/// A visitor that touches every node.
///
/// Stands in for the full-subtree sweep the trivia decision forces on approval-marker lookup,
/// which is the most a rule can ask a tree to do. Counting is only there to keep the compiler from
/// optimising the traversal away.
public final class NodeCountingVisitor: SyntaxAnyVisitor {
  public private(set) var nodes = 0

  override public func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    nodes += 1
    return .visitChildren
  }
}
