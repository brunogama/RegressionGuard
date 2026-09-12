import Foundation

/// The syntax that decides what a production function actually does.
///
/// The keyword matcher this replaces counts *lines* containing `if `, `return`, `catch` and the
/// rest, so a `return` inside a string literal, a comment mentioning `guard `, and one `if`
/// statement spread over four lines all move the count. Counting nodes counts branches.
enum ControlFlowNode {
  static let kinds: Set<SyntaxNodeKind> = [
    .ifExpr, .guardStmt, .switchExpr, .whileStmt, .repeatStmt, .forStmt,
    .doStmt, .catchClause, .throwStmt, .returnStmt,
  ]

  /// Every control-flow node in `tree`, in source order.
  static func nodes(in tree: SyntaxTree) -> [SyntaxNode] {
    tree.nodes(ofAnyKind: kinds)
  }

  /// A short spelling of what a node branches on, for the finding's detail.
  static func description(of node: SyntaxNode) -> String {
    let kind = node.kind.rawValue
    guard let name = node.name else { return kind }
    return kind + " `" + name + "`"
  }
}
