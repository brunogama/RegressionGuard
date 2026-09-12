import Foundation

/// A 1-based, inclusive range of physical source lines.
///
/// Physical lines only: a `#sourceLocation` directive can make a file's presumed lines disagree
/// with the lines a diff talks about, and a finding has to land on a line the author can see.
public struct LineSpan: Codable, Equatable, Hashable, Sendable {
  public let start: Int
  public let end: Int

  public init(start: Int, end: Int) {
    self.start = min(start, end)
    self.end = max(start, end)
  }

  public init(line: Int) {
    self.init(start: line, end: line)
  }

  public var lineNumbers: ClosedRange<Int> { start...end }

  public func contains(line: Int) -> Bool { lineNumbers.contains(line) }

  public func intersects(_ other: Self) -> Bool { start <= other.end && other.start <= end }

  public func intersects(lines: some Sequence<Int>) -> Bool {
    lines.contains { contains(line: $0) }
  }
}

/// The kind of one syntax node, carrying swift-syntax's own `SyntaxKind` spelling.
///
/// A raw string rather than a closed enum, so a node kind RegressionGuardKit has no constant for
/// still survives the projection instead of collapsing into an `unknown` case that rules cannot
/// tell apart.
public struct SyntaxNodeKind: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

public extension SyntaxNodeKind {
  static let sourceFile = Self("sourceFile")
  static let importDecl = Self("importDecl")
  static let classDecl = Self("classDecl")
  static let structDecl = Self("structDecl")
  static let enumDecl = Self("enumDecl")
  static let actorDecl = Self("actorDecl")
  static let extensionDecl = Self("extensionDecl")
  static let functionDecl = Self("functionDecl")
  static let initializerDecl = Self("initializerDecl")
  static let variableDecl = Self("variableDecl")
  static let attribute = Self("attribute")
  static let codeBlock = Self("codeBlock")
  static let closureExpr = Self("closureExpr")
  static let functionCallExpr = Self("functionCallExpr")
  static let memberAccessExpr = Self("memberAccessExpr")
  static let declReferenceExpr = Self("declReferenceExpr")
  static let macroExpansionExpr = Self("macroExpansionExpr")
  static let booleanLiteralExpr = Self("booleanLiteralExpr")
  static let integerLiteralExpr = Self("integerLiteralExpr")
  static let stringLiteralExpr = Self("stringLiteralExpr")
  static let forceUnwrapExpr = Self("forceUnwrapExpr")
  static let optionalChainingExpr = Self("optionalChainingExpr")
  static let tryExpr = Self("tryExpr")
  static let ifExpr = Self("ifExpr")
  static let switchExpr = Self("switchExpr")
  static let guardStmt = Self("guardStmt")
  static let whileStmt = Self("whileStmt")
  static let forStmt = Self("forStmt")
  static let doStmt = Self("doStmt")
  static let catchClause = Self("catchClause")
  static let throwStmt = Self("throwStmt")
  static let returnStmt = Self("returnStmt")
}

/// One node of a parsed file, projected into a type RegressionGuardKit can own.
///
/// The projection is deliberately narrow: kind, line span, name, attributes, and comment trivia
/// are everything the in-scope rule families read. Rule logic stays in RegressionGuardKit, which
/// has no package dependencies and therefore cannot hold a `Syntax` value of its own.
public struct SyntaxNode: Codable, Equatable, Sendable {
  public let kind: SyntaxNodeKind
  /// The physical lines this node occupies in the file it was parsed from.
  public let span: LineSpan
  /// The name this node declares or references, when it carries one.
  public let name: String?
  /// Attribute names written on this node, without the leading `@`.
  public let attributes: [String]
  /// Comment text from this node's own leading and trailing trivia, in source order.
  ///
  /// Approval markers ride in comments, so a missed comment is a missed approval. The projection
  /// owes all four comment trivia cases - `lineComment`, `blockComment`, `docLineComment`,
  /// `docBlockComment` - from leading and trailing trivia both, because upstream leaves trivia
  /// attachment undocumented and a marker can land on either side of the node it authorizes.
  /// Read comments through a sweep (`allComments`, `hasComment(containing:)`) rather than off one
  /// node, for the same reason.
  public let comments: [String]
  public let children: [Self]

  public init(
    kind: SyntaxNodeKind,
    span: LineSpan,
    name: String? = nil,
    attributes: [String] = [],
    comments: [String] = [],
    children: [Self] = []
  ) {
    self.kind = kind
    self.span = span
    self.name = name
    self.attributes = attributes
    self.comments = comments
    self.children = children
  }

  /// Every node below this one, depth first in source order.
  public var descendants: [Self] {
    children.flatMap { [$0] + $0.descendants }
  }

  /// This node and everything below it, depth first in source order.
  public var selfAndDescendants: [Self] { [self] + descendants }

  /// The lines where this node's own syntax is written: its span, less the interior of every
  /// child.
  ///
  /// A child's first line is kept, because a body's opening brace usually sits on the very
  /// signature line that identifies the declaration - subtracting the whole child span would
  /// leave a single-line signature owning nothing. Everything below that line belongs to the
  /// child, so a body edit is not mistaken for a change to the declaration around it.
  ///
  /// Two costs follow from working off spans alone, both bounded by how the projection shapes a
  /// node's children: an edit to a lone `{` line counts as the declaration's own, and a
  /// multi-line signature whose later lines are projected as a child loses them to that child.
  public var ownLines: Set<Int> {
    var lines = Set(span.lineNumbers)
    for child in children where child.span.end > child.span.start {
      lines.subtract((child.span.start + 1)...child.span.end)
    }
    return lines
  }

  public func hasAttribute(named name: String) -> Bool {
    attributes.contains(name)
  }

  public func nodes(ofKind kind: SyntaxNodeKind) -> [Self] {
    selfAndDescendants.filter { $0.kind == kind }
  }

  public func nodes(ofKind kind: SyntaxNodeKind, intersecting span: LineSpan) -> [Self] {
    nodes(ofKind: kind).filter { $0.span.intersects(span) }
  }

  public func firstNode(ofKind kind: SyntaxNodeKind) -> Self? {
    selfAndDescendants.first { $0.kind == kind }
  }

  /// Comment trivia from this node and everything below it, in source order.
  public var allComments: [String] {
    selfAndDescendants.flatMap(\.comments)
  }

  /// - Returns: `true` when `text` appears in a comment on this node or anything below it,
  ///   ignoring case. The sweep is deliberate: trivia attachment is undocumented upstream, so an
  ///   approval marker written against a declaration can land on a neighbouring node.
  public func hasComment(containing text: String) -> Bool {
    let needle = text.lowercased()
    return allComments.contains { $0.lowercased().contains(needle) }
  }
}

/// One file parsed at one ref.
///
/// swift-syntax's parser is error tolerant, so ill-formed source still yields a tree. That makes
/// a parse failure a confidence signal (`hasParseErrors`) rather than a missing-evidence case -
/// the missing-evidence cases are in `SyntaxTreeAvailability`.
public struct SyntaxTree: Codable, Equatable, Sendable {
  /// The path the source was read from, as it exists at `ref`.
  public let path: String
  /// The ref the source was read at, so a finding can say which side it came from.
  public let ref: String
  public let root: SyntaxNode
  public let lineCount: Int
  /// `true` when the parser recovered from ill-formed source. The tree is still usable, but a
  /// rule may prefer to treat its own conclusions as lower confidence.
  public let hasParseErrors: Bool

  public init(
    path: String,
    ref: String,
    root: SyntaxNode,
    lineCount: Int,
    hasParseErrors: Bool = false
  ) {
    self.path = path
    self.ref = ref
    self.root = root
    self.lineCount = lineCount
    self.hasParseErrors = hasParseErrors
  }

  public func nodes(ofKind kind: SyntaxNodeKind) -> [SyntaxNode] {
    root.nodes(ofKind: kind)
  }

  public func nodes(ofKind kind: SyntaxNodeKind, intersecting span: LineSpan) -> [SyntaxNode] {
    root.nodes(ofKind: kind, intersecting: span)
  }

  public func firstNode(ofKind kind: SyntaxNodeKind) -> SyntaxNode? {
    root.firstNode(ofKind: kind)
  }

  /// Every comment in the file, for approval-marker sweeps.
  public var comments: [String] { root.allComments }

  /// - Returns: `true` when `text` appears in any comment in the file, ignoring case.
  public func hasComment(containing text: String) -> Bool {
    root.hasComment(containing: text)
  }
}
