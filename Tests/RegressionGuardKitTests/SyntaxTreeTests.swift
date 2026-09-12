import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Syntax tree tests")
struct SyntaxTreeTests {
  @Test("a span covers its inclusive line range")
  func spanCoversInclusiveRange() {
    let span = LineSpan(start: 10, end: 12)

    #expect(span.lineNumbers == 10...12)
    #expect(span.contains(line: 10))
    #expect(span.contains(line: 12))
    #expect(!span.contains(line: 13))
  }

  @Test("a single-line span starts and ends on the same line")
  func singleLineSpan() {
    let span = LineSpan(line: 7)

    #expect(span.start == 7)
    #expect(span.end == 7)
  }

  @Test("a span reports whether it overlaps changed lines")
  func spanIntersection() {
    let span = LineSpan(start: 10, end: 20)

    #expect(span.intersects(LineSpan(line: 10)))
    #expect(span.intersects(LineSpan(line: 20)))
    #expect(span.intersects(LineSpan(start: 1, end: 100)))
    #expect(!span.intersects(LineSpan(line: 9)))
    #expect(!span.intersects(LineSpan(start: 21, end: 30)))
    #expect(span.intersects(lines: [3, 15]))
    #expect(!span.intersects(lines: [3, 30]))
  }

  @Test("an inverted span is normalized rather than rejected")
  func invertedSpanIsNormalized() {
    let span = LineSpan(start: 12, end: 4)

    #expect(span.start == 4)
    #expect(span.end == 12)
  }

  @Test("node kinds compare by their swift-syntax raw value")
  func nodeKindRawValues() {
    #expect(SyntaxNodeKind.functionDecl.rawValue == "functionDecl")
    #expect(SyntaxNodeKind("functionDecl") == .functionDecl)
    #expect(SyntaxNodeKind("someFutureKind") != .functionDecl)
  }

  @Test("descendants are visited depth first in source order")
  func descendantsAreDepthFirst() {
    let tree = Self.sampleTree()

    let kinds = tree.root.descendants.map(\.kind)
    #expect(
      kinds == [
        .classDecl, .functionDecl, .codeBlock, .functionCallExpr, .booleanLiteralExpr,
        .functionDecl, .codeBlock, .forceUnwrapExpr,
      ]
    )
  }

  @Test("nodes can be looked up by kind")
  func nodesByKind() {
    let tree = Self.sampleTree()

    #expect(tree.nodes(ofKind: .functionDecl).map(\.name) == ["testAnswer", "loadAnswer"])
    #expect(tree.firstNode(ofKind: .forceUnwrapExpr)?.span == LineSpan(line: 8))
    #expect(tree.firstNode(ofKind: .guardStmt) == nil)
    #expect(tree.nodes(ofKind: .guardStmt).isEmpty)
  }

  @Test("nodes can be narrowed to the lines a change touched")
  func nodesIntersectingChangedLines() {
    let tree = Self.sampleTree()

    let touched = tree.nodes(ofKind: .functionDecl, intersecting: LineSpan(start: 7, end: 9))
    #expect(touched.map(\.name) == ["loadAnswer"])
    #expect(tree.nodes(ofKind: .functionDecl, intersecting: LineSpan(line: 100)).isEmpty)
  }

  @Test("attributes and comments are carried on the node they annotate")
  func attributesAndComments() {
    let tree = Self.sampleTree()

    let test = tree.firstNode(ofKind: .functionDecl)
    #expect(test?.attributes == ["Test"])
    #expect(test?.comments == ["// regression-guard:approve"])
    #expect(test?.hasAttribute(named: "Test") == true)
    #expect(test?.hasAttribute(named: "Disabled") == false)
  }

  @Test("comments are collected across the whole tree for marker sweeps")
  func commentsAcrossTree() {
    let tree = Self.sampleTree()

    #expect(tree.comments.contains("// regression-guard:approve"))
    #expect(tree.comments.count == 2)
  }

  @Test("a marker in a comment is found wherever trivia attached it")
  func commentMarkerSweep() {
    let tree = Self.sampleTree()

    #expect(tree.hasComment(containing: "regression-guard:approve"))
    #expect(tree.hasComment(containing: "REGRESSION-GUARD:APPROVE"))
    #expect(!tree.hasComment(containing: "regression-guard:ignore"))
    // Found from any ancestor, not just the node it was written against.
    #expect(tree.root.hasComment(containing: "regression-guard:approve"))
  }

  @Test("a node's own lines exclude its children's interiors")
  func ownLines() {
    let test = Self.sampleTree().root.descendants.first { $0.name == "testAnswer" }

    // `func testAnswer()` on line 2, body open on line 3 and running to line 5. Line 3 stays the
    // declaration's own, because a body's brace as often as not sits on the signature line and
    // the projection cannot tell the two layouts apart from spans alone.
    #expect(test?.ownLines == [2, 3])
  }

  @Test("a childless node owns every line of its span")
  func childlessNodeOwnsItsSpan() {
    let node = SyntaxNode(kind: .functionCallExpr, span: LineSpan(start: 4, end: 6))

    #expect(node.ownLines == [4, 5, 6])
  }

  @Test("a node keeps the line a multi-line child opens on")
  func nodeKeepsTheLineAChildOpensOn() {
    let node = SyntaxNode(
      kind: .functionDecl,
      span: LineSpan(start: 1, end: 4),
      children: [SyntaxNode(kind: .codeBlock, span: LineSpan(start: 1, end: 4))]
    )

    #expect(node.ownLines == [1])
  }

  @Test("a recovered parse is usable but flagged")
  func recoveredParseIsFlagged() {
    let tree = SyntaxTree(
      path: "Sources/Broken.swift",
      ref: "HEAD",
      root: SyntaxNode(kind: .sourceFile, span: LineSpan(start: 1, end: 3)),
      lineCount: 3,
      hasParseErrors: true
    )

    #expect(tree.hasParseErrors)
    #expect(tree.lineCount == 3)
  }

  @Test("a tree round-trips through Codable")
  func treeRoundTripsThroughCodable() throws {
    let tree = Self.sampleTree()

    let data = try JSONEncoder().encode(tree)
    let decoded = try JSONDecoder().decode(SyntaxTree.self, from: data)

    #expect(decoded == tree)
  }

  /// A hand-built stand-in for a parsed file. Real trees come from the parsing target;
  /// rules are unit tested against fixtures like this one.
  static func sampleTree() -> SyntaxTree {
    let assertion = SyntaxNode(
      kind: .functionCallExpr,
      span: LineSpan(line: 4),
      name: "XCTAssertTrue",
      children: [
        SyntaxNode(kind: .booleanLiteralExpr, span: LineSpan(line: 4), name: "true")
      ]
    )
    let test = SyntaxNode(
      kind: .functionDecl,
      span: LineSpan(start: 2, end: 5),
      name: "testAnswer",
      attributes: ["Test"],
      comments: ["// regression-guard:approve"],
      children: [
        SyntaxNode(kind: .codeBlock, span: LineSpan(start: 3, end: 5), children: [assertion])
      ]
    )
    let loader = SyntaxNode(
      kind: .functionDecl,
      span: LineSpan(start: 7, end: 9),
      name: "loadAnswer",
      comments: ["// force unwrap is fine here"],
      children: [
        SyntaxNode(
          kind: .codeBlock,
          span: LineSpan(start: 7, end: 9),
          children: [SyntaxNode(kind: .forceUnwrapExpr, span: LineSpan(line: 8))]
        )
      ]
    )
    return SyntaxTree(
      path: "Tests/ExampleTests.swift",
      ref: "HEAD",
      root: SyntaxNode(
        kind: .sourceFile,
        span: LineSpan(start: 1, end: 10),
        children: [
          SyntaxNode(
            kind: .classDecl,
            span: LineSpan(start: 1, end: 10),
            name: "ExampleTests",
            children: [test, loader]
          )
        ]
      ),
      lineCount: 10
    )
  }
}
