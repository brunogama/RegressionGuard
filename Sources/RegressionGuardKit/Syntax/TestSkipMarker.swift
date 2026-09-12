import Foundation

/// The syntax that stops a test from running.
///
/// Reading these off the tree rather than off added lines removes the whole class of false
/// positives the text matcher has to work around: a test *named* `testFlagsXCTSkipAddedToATest`,
/// a string payload containing `.disabled(`, a comment describing a skip. None of those are
/// marker nodes, so none of them are found here, and the declared-name workaround the line path
/// needs has no counterpart on the tree.
enum TestSkipMarker {
  /// Trait names that switch a test or suite off.
  ///
  /// Written as `@Test(.disabled)` or `@Suite(.disabled("reason"))`, so they are references inside
  /// an attribute rather than attributes of their own.
  private static let disablingTraits = ["disabled"]

  /// Attributes that switch a test off by being present.
  private static let disablingAttributes = ["Disabled"]

  /// Calls that abandon a running test.
  ///
  /// Matched by prefix, which covers `XCTSkipIf` and `XCTSkipUnless` alongside `XCTSkip`.
  private static let skipCallPrefixes = ["XCTSkip"]

  /// Every node in `tree` that stops a test running, in source order.
  static func markers(in tree: SyntaxTree) -> [SyntaxNode] {
    traitMarkers(in: tree) + skipCalls(in: tree)
  }

  /// A human-readable name for the marker, for the finding's detail.
  static func description(of node: SyntaxNode) -> String {
    guard let name = node.name else { return node.kind.rawValue }
    return node.kind == .attribute ? "@" + name : name
  }

  /// Disabling traits and attributes, found inside attribute nodes only.
  ///
  /// Scoped to attributes on purpose: `.disabled` is a test trait where it is written on a
  /// declaration, and an ordinary member call anywhere else.
  private static func traitMarkers(in tree: SyntaxTree) -> [SyntaxNode] {
    tree.nodes(ofKind: .attribute).flatMap { attribute -> [SyntaxNode] in
      if let name = attribute.name, disablingAttributes.contains(name) { return [attribute] }
      return disablingTraits.flatMap { attribute.nodes(named: $0) }
    }
  }

  private static func skipCalls(in tree: SyntaxTree) -> [SyntaxNode] {
    tree.nodes(ofAnyKind: [.functionCallExpr, .macroExpansionExpr]).filter { node in
      guard let name = node.name else { return false }
      return skipCallPrefixes.contains { name.hasPrefix($0) }
    }
  }
}
