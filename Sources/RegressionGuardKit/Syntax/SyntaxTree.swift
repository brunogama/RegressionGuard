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
  /// Comment text from this node's own leading and trailing trivia, in source order. Approval
  /// markers ride in comments, and upstream leaves trivia attachment undocumented, so the
  /// projection keeps both sides on the node they were written against.
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
}
