import Foundation

/// One piece of syntax that stops a test from running, and where a finding on it belongs.
///
/// Reading these off the tree rather than off added lines removes the whole class of false
/// positives the text matcher has to work around: a test *named* `testFlagsXCTSkipAddedToATest`,
/// a string payload containing `.disabled(`, a comment describing a skip. None of those are
/// marker nodes, so none of them are found here, and the declared-name workaround the line path
/// needs has no counterpart on the tree.
struct TestSkipMarker {
  /// How the marker is written, for the finding's detail.
  let label: String
  /// The node a finding is anchored to.
  let node: SyntaxNode
  /// `true` when `node` is the marker itself, so any change inside its span is a change to it.
  ///
  /// `false` when the marker was only legible on the declaration carrying it - an attribute the
  /// projection kept as a string has no node of its own. A declaration's span covers its whole
  /// body, so only a change to its own lines can be this marker's doing; anything else is a body
  /// edit under a test that was already switched off.
  let isPrecise: Bool
}

extension TestSkipMarker {
  /// Trait names that switch a test or suite off.
  ///
  /// Written as `@Test(.disabled)` or `@Suite(.disabled("reason"))`, so they live inside an
  /// attribute rather than being attributes of their own.
  private static let disablingTraits = ["disabled"]

  /// Attributes that switch a test off by being present.
  private static let disablingAttributes = ["Disabled"]

  /// Calls that abandon a running test.
  ///
  /// Matched by prefix, which covers `XCTSkipIf` and `XCTSkipUnless` alongside `XCTSkip`.
  private static let skipCallPrefixes = ["XCTSkip"]

  /// Everything in `tree` that stops a test running, in source order.
  static func markers(in tree: SyntaxTree) -> [Self] {
    tree.root.selfAndDescendants.flatMap(declarationMarkers) + skipCalls(in: tree)
  }

  /// Markers written on one declaration, in whichever shape the projection used.
  ///
  /// Both shapes are read. `attributes` is the documented carrier and an `attribute` child node is
  /// what a faithful projection of swift-syntax's own tree gives, so a rule that read only one of
  /// them would go quiet - not wrong, quiet - against the other. A marker found as a node anchors
  /// to itself; one legible only as a string anchors to the declaration.
  private static func declarationMarkers(on node: SyntaxNode) -> [Self] {
    var markers = node.attributeNodes
      .filter { $0.name.map(disablingAttributes.contains) ?? false }
      .map { Self(label: "@" + ($0.name ?? ""), node: $0, isPrecise: true) }

    markers +=
      disablingAttributes
      .filter { node.attributes.contains($0) }
      .map { Self(label: "@" + $0, node: node, isPrecise: false) }

    for trait in disablingTraits {
      markers += node.attributeTraitNodes(named: trait)
        .map { Self(label: "." + trait, node: $0, isPrecise: true) }
      markers += node.attributeSpellings(containingTrait: trait)
        .map { Self(label: "@" + $0, node: node, isPrecise: false) }
    }
    return markers
  }

  private static func skipCalls(in tree: SyntaxTree) -> [Self] {
    tree.nodes(ofAnyKind: [.functionCallExpr, .macroExpansionExpr]).compactMap { node in
      guard let name = node.name, skipCallPrefixes.contains(where: name.hasPrefix) else {
        return nil
      }
      return Self(label: name, node: node, isPrecise: true)
    }
  }
}
