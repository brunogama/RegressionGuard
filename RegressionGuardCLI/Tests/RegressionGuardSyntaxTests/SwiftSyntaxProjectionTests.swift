import RegressionGuardKit
import Testing

@testable import RegressionGuardSyntax

@Suite("Swift syntax projection tests")
struct SwiftSyntaxProjectionTests {
  private func tree(_ source: String) -> SyntaxTree {
    SwiftSyntaxProjection.tree(source: source, path: "F.swift", ref: "HEAD")
  }

  @Test("projects a declaration with the kind and span rules match on")
  func projectsDeclaration() throws {
    let parsed = tree(
      """
      func compute(x: Int) -> Int {
        return x
      }
      """
    )
    let function = try #require(parsed.firstNode(ofKind: .functionDecl))
    #expect(function.name == "compute")
    #expect(function.span == LineSpan(start: 1, end: 3))
    #expect(parsed.lineCount == 3)
    #expect(!parsed.hasParseErrors)
  }

  @Test("carries attribute names without the leading at sign")
  func carriesAttributes() throws {
    let parsed = tree(
      """
      @MainActor
      @available(macOS 14, *)
      func run() {}
      """
    )
    let function = try #require(parsed.firstNode(ofKind: .functionDecl))
    #expect(function.hasAttribute(named: "MainActor"))
    #expect(function.hasAttribute(named: "available"))
  }

  @Test("reads all four comment trivia cases, since an approval marker rides in any of them")
  func readsEveryCommentShape() {
    let parsed = tree(
      """
      // line
      /* block */
      /// doc line
      /** doc block */
      func run() {} // trailing
      """
    )
    let comments = parsed.comments.joined(separator: "\n")
    #expect(comments.contains("// line"))
    #expect(comments.contains("/* block */"))
    #expect(comments.contains("/// doc line"))
    #expect(comments.contains("/** doc block */"))
    #expect(comments.contains("// trailing"))
  }

  @Test("attaches each comment once rather than to every ancestor sharing the token")
  func attachesEachCommentOnce() {
    let parsed = tree("// only once\nfunc run() {}")
    #expect(parsed.comments.filter { $0.contains("only once") }.count == 1)
  }

  @Test("finds an approval marker written anywhere in the file")
  func findsApprovalMarker() {
    let parsed = tree("func run() {\n  // regression-guard: approved\n  return\n}")
    #expect(parsed.hasComment(containing: "REGRESSION-GUARD: APPROVED"))
  }

  @Test("separates try from the spellings that discard the error")
  func separatesTrySpellings() {
    let forced = tree("func f() { _ = try! g() }").firstNode(ofKind: .tryExpr)
    let optional = tree("func f() { _ = try? g() }").firstNode(ofKind: .tryExpr)
    let propagating = tree("func f() throws { _ = try g() }").firstNode(ofKind: .tryExpr)
    #expect(forced?.name == "try!")
    #expect(optional?.name == "try?")
    #expect(propagating?.name == "try")
  }

  @Test("keeps a macro's hash, so a rule matches what the author wrote")
  func keepsMacroHash() {
    let parsed = tree("func f() { #expect(x == 1) }")
    #expect(parsed.firstNode(ofKind: .macroExpansionExpr)?.name == "#expect")
  }

  @Test("names a call's callee on the call rather than only on a child")
  func namesCallee() throws {
    let parsed = tree("func f() { XCTAssertTrue(x) }")
    let call = try #require(parsed.firstNode(ofKind: .functionCallExpr))
    #expect(call.firstNode(ofKind: .declReferenceExpr)?.name == "XCTAssertTrue")
  }

  @Test("drops empty collection nodes, which have no honest span")
  func dropsEmptyCollections() throws {
    // An unattributed declaration still carries an `attributeList`; upstream collapses its span
    // onto the preceding line, which would put a node where no source is written.
    let parsed = tree("let a = 1\nfunc run() {}")
    let function = try #require(parsed.firstNode(ofKind: .functionDecl))
    #expect(function.selfAndDescendants.allSatisfy { $0.span.start >= 2 })
  }

  @Test("a node's own lines exclude the interior of its children")
  func ownLinesExcludeChildInteriors() throws {
    let parsed = tree(
      """
      func outer() {
        let a = 1
        let b = 2
      }
      """
    )
    let function = try #require(parsed.firstNode(ofKind: .functionDecl))
    #expect(function.ownLines.contains(1))
    #expect(!function.ownLines.contains(3))
  }
}
