import Foundation

public extension SyntaxNode {
  /// The attribute nodes written on this node, when the projection shapes them as children.
  var attributeNodes: [Self] { children.filter { $0.kind == .attribute } }

  /// Attribute names written on this node, read from both shapes a projection may use.
  ///
  /// `attributes` is the documented carrier, and an `attribute` child node is the shape a faithful
  /// projection of swift-syntax's own tree produces. Reading only one of the two would let the
  /// other spelling answer "no attributes here", which reads exactly like a declaration that
  /// carries none - a detection switched off by a projection choice, with nothing to show for it.
  /// An entry in `attributes` may carry its arguments too (`Test(.disabled)`), so the name is
  /// taken up to the opening parenthesis.
  var attributeNames: [String] {
    attributes.map { Self.attributeName(in: $0) } + attributeNodes.compactMap(\.name)
  }

  /// - Returns: `true` when this node is written with `@name`, in either projection shape.
  func carriesAttribute(named name: String) -> Bool { attributeNames.contains(name) }

  /// - Returns: the nodes for `trait` written inside this node's attributes, such as the
  ///   `.disabled` in `@Test(.disabled)`. Empty when the projection kept the attribute as a
  ///   string; `attributeSpellings(containingTrait:)` answers that shape.
  func attributeTraitNodes(named trait: String) -> [Self] {
    attributeNodes.flatMap { $0.nodes(named: trait) }
  }

  /// - Returns: the `attributes` entries that carry `.trait` in their spelling, for a projection
  ///   that kept an attribute's arguments as text rather than as child nodes.
  func attributeSpellings(containingTrait trait: String) -> [String] {
    attributes.filter { $0.contains("." + trait) }
  }

  private static func attributeName(in spelling: String) -> String {
    String(spelling.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces)
  }

  /// The statements this node holds, in source order, in either projection shape.
  ///
  /// swift-syntax puts a block's statements inside a `CodeBlockItemList` rather than directly
  /// under the block, and wraps each one in a `CodeBlockItem` besides. A projection faithful to
  /// either layer hands back wrappers where a rule expected statements, so the rule finds no
  /// `returnStmt` and no trap and concludes the body was fine - silence, not error, which is the
  /// failure this projection is most prone to. Both wrappers are unwrapped here rather than in
  /// every rule that reads a block, and both shapes are pinned by tests.
  ///
  /// The item wrapper was found by running the real projector rather than by reading it: the
  /// list was absorbed and the item was not, which left `implementation_stubbed` and
  /// `unreachable_assertion` reporting nothing on real source while their fixtures passed.
  var statements: [Self] {
    children
      .flatMap { $0.kind == .codeBlockItemList ? $0.children : [$0] }
      .flatMap { $0.kind == .codeBlockItem ? $0.children : [$0] }
  }

  /// The statements of this declaration's body, in either projection shape.
  var bodyStatements: [Self] {
    children.first { $0.kind == .codeBlock }?.statements ?? []
  }

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
