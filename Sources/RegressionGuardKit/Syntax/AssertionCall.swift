import Foundation

/// The assertion calls a parsed test file makes, and whether one of them can still fail.
///
/// The text matcher this replaces compares whole lines against a hardcoded list of exact
/// spellings, so `XCTAssertTrue( true )`, `#expect(1 == 1)` and `XCTAssertEqual(2, 2)` all read as
/// healthy assertions today. A tautology is not a spelling, it is a call whose result cannot
/// depend on the code under test, which is a question about the call's arguments.
enum AssertionCall {
  /// Call kinds an assertion can be written as. `#expect` and `#require` are macros, the
  /// `XCTAssert` family are functions.
  static let kinds: Set<SyntaxNodeKind> = [.functionCallExpr, .macroExpansionExpr]

  /// Callee names that assert.
  ///
  /// Matched by prefix, which covers the whole `XCTAssert*` family without listing it.
  private static let prefixes = ["XCTAssert", "XCTFail", "XCTUnwrap", "expect", "require"]

  /// `XCTFail` states an unconditional failure, so its literal-only argument is the correct way to
  /// write it rather than a weakened assertion.
  private static let unconditional = ["XCTFail"]

  /// Argument shapes that make an assertion depend on something the code under test produces.
  ///
  /// Anything else in an argument is a constant the author wrote into the assertion itself.
  private static let runtimeValueKinds: Set<SyntaxNodeKind> = [
    .declReferenceExpr, .memberAccessExpr, .functionCallExpr, .macroExpansionExpr,
    .closureExpr, .forceUnwrapExpr, .optionalChainingExpr, .tryExpr,
  ]

  private static let literalKinds: Set<SyntaxNodeKind> = [
    .booleanLiteralExpr, .integerLiteralExpr, .floatLiteralExpr, .stringLiteralExpr,
    .nilLiteralExpr,
  ]

  /// Every assertion call in `tree`, in source order.
  static func calls(in tree: SyntaxTree) -> [SyntaxNode] {
    tree.nodes(ofAnyKind: kinds).filter { isAssertion($0) }
  }

  static func isAssertion(_ node: SyntaxNode) -> Bool {
    guard let name = calleeName(of: node) else { return false }
    return prefixes.contains { name.hasPrefix($0) }
  }

  /// - Returns: `true` when nothing this call is given can vary at run time, so the assertion
  ///   reaches the same verdict whatever the code under test does.
  static func cannotFail(_ node: SyntaxNode) -> Bool {
    guard let name = calleeName(of: node), !unconditional.contains(name) else { return false }
    let arguments = argumentNodes(of: node)
    guard arguments.contains(where: { literalKinds.contains($0.kind) }) else { return false }
    return !arguments.contains { runtimeValueKinds.contains($0.kind) }
  }

  /// Everything the call was given, with the thing being called left out.
  ///
  /// swift-syntax makes a call's callee a child of the call, so a faithful projection puts
  /// `XCTAssertTrue` in the subtree as a `declReferenceExpr` - a run-time value by the reckoning
  /// above, which would make every assertion look like it could fail and quietly switch this
  /// detection off. The callee is dropped here whether or not the projector also hoists it into
  /// the node's name, so either projection gives the same answer rather than one of them failing
  /// silently.
  private static func argumentNodes(of node: SyntaxNode) -> [SyntaxNode] {
    node.children
      .filter { !isCallee($0, of: node) }
      .flatMap(\.selfAndDescendants)
  }

  private static func isCallee(_ child: SyntaxNode, of node: SyntaxNode) -> Bool {
    guard calleeKinds.contains(child.kind), let name = child.name else { return false }
    return name == node.name || name == calleeName(of: node)
  }

  /// How a callee is written: a bare name, or the trailing member of a qualified one.
  private static let calleeKinds: Set<SyntaxNodeKind> = [.declReferenceExpr, .memberAccessExpr]

  /// The name the call invokes.
  ///
  /// A macro is projected without its `#`, but a leading `#` is tolerated so a projector spelling
  /// it either way still matches.
  static func calleeName(of node: SyntaxNode) -> String? {
    guard let name = node.name else { return nil }
    return name.hasPrefix("#") ? String(name.dropFirst()) : name
  }
}
