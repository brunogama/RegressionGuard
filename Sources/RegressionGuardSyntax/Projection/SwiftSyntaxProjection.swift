import RegressionGuardKit
import SwiftParser
import SwiftSyntax

/// Parses Swift source into the structural projection RegressionGuardKit owns.
///
/// The boundary is the point. RegressionGuardKit holds the rule logic and has no package
/// dependencies, so it cannot hold a `Syntax` value; this target holds swift-syntax and hands back
/// `SyntaxTree`. Everything swift-syntax-shaped stops here.
public enum SwiftSyntaxProjection {
  /// Parses `source` and projects it.
  ///
  /// Never fails. SwiftParser is error tolerant by contract, so ill-formed source yields a tree
  /// carrying unexpected nodes and missing tokens rather than an error - which is what lets a
  /// grammar gap be scoped to the region it damages instead of condemning the file.
  ///
  /// - Parameters:
  ///   - source: the file's full text.
  ///   - path: the path the source was read from, as it exists at `ref`.
  ///   - ref: the ref the source was read at.
  public static func tree(source: String, path: String, ref: String) -> SyntaxTree {
    let parsed = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: path, tree: parsed)
    let lineCount = converter.location(for: parsed.endPosition).line
    let root = node(Syntax(parsed), converter: converter)
      ?? SyntaxNode(kind: .sourceFile, span: LineSpan(start: 1, end: max(lineCount, 1)))
    return SyntaxTree(
      path: path,
      ref: ref,
      root: root,
      lineCount: lineCount,
      hasParseErrors: parsed.hasError
    )
  }

  /// Projects one node and its non-token children, or `nil` when the node writes no source.
  ///
  /// An empty collection - the `attributeList` of an unattributed declaration, say - has no tokens
  /// and therefore no honest span, and upstream reports one collapsed onto the preceding line.
  /// Dropping those keeps a node's span truthful and keeps the retained tree smaller, which the
  /// parse performance budget makes the tight side of this feature.
  private static func node(_ syntax: Syntax, converter: SourceLocationConverter) -> SyntaxNode? {
    let children = syntax.children(viewMode: .sourceAccurate)
    guard let span = span(of: syntax, converter: converter) else { return nil }
    return SyntaxNode(
      kind: SyntaxNodeKind(String(describing: syntax.kind)),
      span: span,
      name: SyntaxNodeName.of(syntax),
      attributes: attributeNames(of: syntax),
      comments: comments(of: children),
      hasError: holdsUnrepresentableSyntax(syntax, children: children),
      children: children.compactMap { child in
        child.as(TokenSyntax.self) == nil ? node(child, converter: converter) : nil
      }
    )
  }

  /// The physical lines the node's own tokens occupy, ignoring the trivia around them.
  ///
  /// Trivia is excluded deliberately: a node's leading trivia reaches back over the blank lines and
  /// comments before it, and a span stretched that far would make a comment edit read as a change
  /// to the declaration below it.
  private static func span(
    of syntax: Syntax,
    converter: SourceLocationConverter
  ) -> LineSpan? {
    guard syntax.firstToken(viewMode: .sourceAccurate) != nil else { return nil }
    return LineSpan(
      start: syntax.startLocation(converter: converter, afterLeadingTrivia: true).line,
      end: syntax.endLocation(converter: converter, afterTrailingTrivia: false).line
    )
  }

  /// Attribute names written on this node, without the leading `@`.
  private static func attributeNames(of syntax: Syntax) -> [String] {
    guard let attributed = syntax.asProtocol(WithAttributesSyntax.self) else { return [] }
    return attributed.attributes.compactMap { element in
      element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
    }
  }

  /// Comment text from the trivia of this node's own tokens, in source order.
  ///
  /// Read off direct token children rather than the node's leading and trailing trivia, because
  /// trivia belongs to a token and every ancestor sharing that first token would otherwise claim
  /// the same comment. Attaching it once, to the node that directly holds the token, keeps
  /// `SyntaxNode.allComments` a sweep rather than a multiplication.
  private static func comments(of children: SyntaxChildren) -> [String] {
    children.compactMap { $0.as(TokenSyntax.self) }
      .flatMap { token in token.leadingTrivia + token.trailingTrivia }
      .compactMap { piece in
        switch piece {
        case .lineComment(let text), .blockComment(let text),
          .docLineComment(let text), .docBlockComment(let text):
          return text
        default:
          return nil
        }
      }
  }

  /// `true` when this node directly holds syntax the parser could not represent.
  ///
  /// Node-local by contract. The two shapes upstream uses are an `UnexpectedNodesSyntax` holding
  /// tokens it could not place, and a missing token standing in for one the grammar required. Only
  /// the node directly holding either is marked: propagating upwards would mark the whole file,
  /// and a grammar gap that cannot be scoped to a region has to fail the entire run.
  private static func holdsUnrepresentableSyntax(
    _ syntax: Syntax,
    children: SyntaxChildren
  ) -> Bool {
    if syntax.is(UnexpectedNodesSyntax.self) { return true }
    return children.contains { $0.as(TokenSyntax.self)?.presence == .missing }
  }
}
