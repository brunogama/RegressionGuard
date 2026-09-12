import Foundation
@testable import RegressionGuardKit

/// Hand-built stand-ins for parsed files, for the rules that read trees.
///
/// The projector that turns real Swift into these values is a later ticket, so a rule is unit
/// tested against the projection it is promised rather than against a parser. The builders below
/// exist so a test reads as the source it stands for, with line numbers that line up with the
/// diff it is paired with.
enum SyntaxFixture {

  // MARK: - Files

  /// A file that exists on both sides.
  static func evidence(
    path: String,
    base: SyntaxTree,
    head: SyntaxTree
  ) -> SyntacticFileEvidence {
    SyntacticFileEvidence(path: path, base: .parsed(base), head: .parsed(head))
  }

  /// A file with a gap on one side, which is what a rule must degrade around.
  static func degradedEvidence(
    path: String,
    reason: SyntaxEvidenceGapReason = .sourceReadFailed
  ) -> SyntacticFileEvidence {
    SyntacticFileEvidence(
      path: path,
      base: .unavailable(reason, detail: nil),
      head: .unavailable(reason, detail: nil)
    )
  }

  static func tree(
    path: String,
    ref: SyntaxRef,
    lineCount: Int = 100,
    _ children: [SyntaxNode]
  ) -> SyntaxTree {
    SyntaxTree(
      path: path,
      ref: ref.rawValue,
      root: SyntaxNode(
        kind: .sourceFile,
        span: LineSpan(start: 1, end: lineCount),
        children: children
      ),
      lineCount: lineCount
    )
  }

  // MARK: - Nodes

  /// A test function, optionally carrying attributes and traits.
  static func function(
    _ name: String,
    lines: ClosedRange<Int>,
    attributes: [SyntaxNode] = [],
    body: [SyntaxNode] = []
  ) -> SyntaxNode {
    SyntaxNode(
      kind: .functionDecl,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: name,
      attributes: attributes.compactMap(\.name),
      children: attributes
        + [
          SyntaxNode(
            kind: .codeBlock,
            span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
            children: body
          )
        ]
    )
  }

  /// An attribute written on a declaration, with its arguments projected as children.
  static func attribute(
    _ name: String,
    line: Int,
    arguments: [SyntaxNode] = []
  ) -> SyntaxNode {
    SyntaxNode(kind: .attribute, span: LineSpan(line: line), name: name, children: arguments)
  }

  /// A trait written inside an attribute, such as the `.disabled` in `@Test(.disabled)`.
  static func trait(_ name: String, line: Int) -> SyntaxNode {
    SyntaxNode(kind: .memberAccessExpr, span: LineSpan(line: line), name: name)
  }

  static func call(
    _ name: String,
    lines: ClosedRange<Int>,
    arguments: [SyntaxNode] = []
  ) -> SyntaxNode {
    SyntaxNode(
      kind: .functionCallExpr,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: name,
      children: arguments
    )
  }

  static func call(
    _ name: String,
    line: Int,
    arguments: [SyntaxNode] = []
  ) -> SyntaxNode {
    call(name, lines: line...line, arguments: arguments)
  }

  /// The same call, projected the way swift-syntax shapes one: the callee is a child of the call,
  /// not only the node's name.
  ///
  /// The projector is a later ticket and could reasonably emit either shape, so the rules have to
  /// read both. A detection that only works against the shape above would switch itself off
  /// silently the day the real projector lands.
  static func callWithCalleeChild(
    _ name: String,
    line: Int,
    arguments: [SyntaxNode] = []
  ) -> SyntaxNode {
    call(name, line: line, arguments: [reference(name, line: line)] + arguments)
  }

  static func macro(_ name: String, line: Int, arguments: [SyntaxNode] = []) -> SyntaxNode {
    SyntaxNode(
      kind: .macroExpansionExpr,
      span: LineSpan(line: line),
      name: name,
      children: arguments
    )
  }

  static func literal(_ kind: SyntaxNodeKind, _ text: String, line: Int) -> SyntaxNode {
    SyntaxNode(kind: kind, span: LineSpan(line: line), name: text)
  }

  /// A value read at run time, which is what stops an assertion being a tautology.
  static func reference(_ name: String, line: Int) -> SyntaxNode {
    SyntaxNode(kind: .declReferenceExpr, span: LineSpan(line: line), name: name)
  }

  static func member(_ name: String, line: Int) -> SyntaxNode {
    SyntaxNode(kind: .memberAccessExpr, span: LineSpan(line: line), name: name)
  }

  /// A comparison of two operands, such as the `1 == 1` inside `#expect(1 == 1)`.
  static func comparison(_ operands: [SyntaxNode], line: Int) -> SyntaxNode {
    SyntaxNode(kind: .infixOperatorExpr, span: LineSpan(line: line), children: operands)
  }

  static func node(
    _ kind: SyntaxNodeKind,
    lines: ClosedRange<Int>,
    name: String? = nil,
    children: [SyntaxNode] = []
  ) -> SyntaxNode {
    SyntaxNode(
      kind: kind,
      span: LineSpan(start: lines.lowerBound, end: lines.upperBound),
      name: name,
      children: children
    )
  }

  // MARK: - Diffs

  /// A one-hunk diff whose line numbers a caller states outright, so a fixture tree's spans and
  /// its diff agree.
  static func diff(
    path: String,
    lines: [DiffLine],
    isDeleted: Bool = false,
    isAdded: Bool = false
  ) -> FileDiff {
    FileDiff(
      oldPath: isAdded ? nil : path,
      newPath: isDeleted ? nil : path,
      isDeleted: isDeleted,
      isAdded: isAdded,
      isRenamed: false,
      hunks: [Hunk(oldStart: 1, newStart: 1, lines: lines)]
    )
  }

  static func bundle(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence?,
    context: RuleContext
  ) -> EvidenceBundle {
    EvidenceBundle(
      fileDiffs: [fileDiff],
      commit: CommitEvidence(baseRef: context.baseRef, headRef: context.headRef, messages: []),
      syntax: SyntacticEvidence(files: syntax.map { [$0] } ?? [])
    )
  }
}
