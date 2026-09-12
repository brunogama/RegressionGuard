import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Changed line map tests")
struct ChangedLineMapTests {

  /// A one-hunk diff of a file that exists on both sides, starting at line 1.
  static func diff(lines: [DiffLine], path: String = "Sources/A.swift") -> FileDiff {
    FileDiff(
      oldPath: path,
      newPath: path,
      isDeleted: false,
      isAdded: false,
      isRenamed: false,
      hunks: [Hunk(oldStart: 1, newStart: 1, lines: lines)]
    )
  }

  /// ```
  ///  1  import Foundation      context   base 1  head 1
  ///  2  func untouched() {}    context   base 2  head 2
  ///  3  let removed = 1        removed   base 3
  ///  4  let alsoRemoved = 2    removed   base 4
  ///  5  let added = 1          added             head 3
  ///  6  let alsoAdded = 2      added             head 4
  ///  7  let thirdAdded = 3     added             head 5
  ///  8  func tail() {}         context   base 5  head 6
  /// ```
  static func mixedHunkDiff(path: String = "Sources/Thing.swift") -> FileDiff {
    diff(
      lines: [
        DiffLine(kind: .context, number: 1, text: "import Foundation"),
        DiffLine(kind: .context, number: 2, text: "func untouched() {}"),
        DiffLine(kind: .removed, number: 3, text: "let removed = 1"),
        DiffLine(kind: .removed, number: 4, text: "let alsoRemoved = 2"),
        DiffLine(kind: .added, number: 3, text: "let added = 1"),
        DiffLine(kind: .added, number: 4, text: "let alsoAdded = 2"),
        DiffLine(kind: .added, number: 5, text: "let thirdAdded = 3"),
        DiffLine(kind: .context, number: 6, text: "func tail() {}"),
      ],
      path: path
    )
  }

  @Test("changed lines are kept per side, in each side's own numbering")
  func changedLinesPerSide() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.changedLines(at: .head) == [3, 4, 5])
    #expect(map.changedLines(at: .base) == [3, 4])
  }

  @Test("a span is in the change only when a changed line falls inside it")
  func spanIsInTheChange() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.touches(LineSpan(start: 1, end: 6), at: .head))
    #expect(map.touches(LineSpan(line: 3), at: .head))
    #expect(!map.touches(LineSpan(start: 1, end: 2), at: .head))
    #expect(!map.touches(LineSpan(line: 6), at: .head))
    #expect(map.touches(LineSpan(start: 3, end: 4), at: .base))
    #expect(!map.touches(LineSpan(start: 1, end: 2), at: .base))
  }

  @Test("changed lines inside a span are reported in source order")
  func changedLinesInsideSpan() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.changedLines(in: LineSpan(start: 1, end: 4), at: .head) == [3, 4])
    #expect(map.changedLines(in: LineSpan(start: 1, end: 2), at: .head) == [])
  }

  // MARK: - Node change scope

  @Test("a node the change never reaches is outside the change")
  func nodeOutsideTheChange() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())
    let node = SyntaxNode(kind: .functionDecl, span: LineSpan(line: 2), name: "untouched")

    #expect(map.changeScope(of: node, at: .head) == .outside)
    #expect(!map.changeScope(of: node, at: .head).isChanged)
  }

  @Test("a body changed under an untouched signature is a nested change")
  func bodyChangedUnderUntouchedSignature() {
    // `func f() {` on line 2, body lines 3 and 4, closing brace on line 5; only line 4 changed.
    let map = ChangedLineMap(
      fileDiff: Self.diff(lines: [DiffLine(kind: .added, number: 4, text: "  return 0")])
    )
    let function = Self.function(span: LineSpan(start: 2, end: 5))

    #expect(map.changeScope(of: function, at: .head) == .nested)
    #expect(map.changeScope(of: function, at: .head).isChanged)
  }

  @Test("a signature changed on the line its body opens on is the node's own change")
  func signatureChangedWhereBodyOpens() {
    // The `{` of the body sits on the signature line, so the signature line stays the node's own.
    let map = ChangedLineMap(
      fileDiff: Self.diff(lines: [DiffLine(kind: .added, number: 2, text: "func f() -> Int {")])
    )
    let function = Self.function(span: LineSpan(start: 2, end: 5))

    #expect(map.changeScope(of: function, at: .head) == .own)
  }

  @Test("a childless node treats any change inside it as its own")
  func childlessNodeOwnsItsWholeSpan() {
    let map = ChangedLineMap(
      fileDiff: Self.diff(lines: [DiffLine(kind: .added, number: 4, text: "  .weakened")])
    )
    let call = SyntaxNode(kind: .functionCallExpr, span: LineSpan(start: 3, end: 5))

    #expect(map.changeScope(of: call, at: .head) == .own)
  }

  @Test("only the nodes the change reaches come back from a tree")
  func changedNodesOfKind() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())
    let tree = SyntaxTree(
      path: "Sources/Thing.swift",
      ref: "head",
      root: SyntaxNode(
        kind: .sourceFile,
        span: LineSpan(start: 1, end: 6),
        children: [
          SyntaxNode(kind: .variableDecl, span: LineSpan(line: 2), name: "untouched"),
          SyntaxNode(kind: .variableDecl, span: LineSpan(line: 3), name: "added"),
          SyntaxNode(kind: .variableDecl, span: LineSpan(line: 5), name: "thirdAdded"),
        ]
      ),
      lineCount: 6
    )

    let changed = map.changedNodes(ofKind: .variableDecl, in: tree, at: .head)

    #expect(changed.map(\.name) == ["added", "thirdAdded"])
  }

  // MARK: - Base to head line mapping

  @Test("a base line that survived maps to its head line")
  func contextLineMapsAcrossTheChange() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.headLine(forBaseLine: 1) == 1)
    #expect(map.headLine(forBaseLine: 2) == 2)
    #expect(map.headLine(forBaseLine: 5) == 6)
  }

  @Test("a deleted base line maps to the head line the deletion left behind")
  func removedLineMapsToItsHeadAnchor() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.headLine(forBaseLine: 3) == 3)
    #expect(map.headLine(forBaseLine: 4) == 3)
  }

  @Test("base lines past the change are shifted by the change's net line delta")
  func linesAfterTheHunkAreShifted() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    // The hunk removed two lines and added three, so everything after it moves down one.
    #expect(map.headLine(forBaseLine: 40) == 41)
  }

  @Test("a real multi-hunk diff translates every base line correctly")
  func multiHunkDiffFromGit() throws {
    // A hunk that nets one line longer, then a hunk that nets one line shorter.
    let raw = """
      diff --git a/Sources/A.swift b/Sources/A.swift
      --- a/Sources/A.swift
      +++ b/Sources/A.swift
      @@ -1,4 +1,5 @@
       one
      -two
      +two changed
      +two extra
       three
       four
      @@ -20,3 +21,2 @@
       twenty
      -twentyone
       twentytwo
      """
    let fileDiff = try #require(GitDiffParser().parse(raw).first)
    let map = ChangedLineMap(fileDiff: fileDiff)

    #expect(map.changedLines(at: .head) == [2, 3])
    #expect(map.changedLines(at: .base) == [2, 21])
    // Inside the first hunk, then between the hunks, where only the first hunk's delta applies.
    #expect(map.headLine(forBaseLine: 1) == 1)
    #expect(map.headLine(forBaseLine: 3) == 4)
    #expect(map.headLine(forBaseLine: 4) == 5)
    #expect(map.headLine(forBaseLine: 10) == 11)
    // Inside the second hunk, and past it, where the two deltas cancel out.
    #expect(map.headLine(forBaseLine: 20) == 21)
    #expect(map.headLine(forBaseLine: 21) == 22)
    #expect(map.headLine(forBaseLine: 22) == 22)
    #expect(map.headLine(forBaseLine: 30) == 30)
  }

  @Test("a deletion running to the end of the file stays inside the file")
  func trailingDeletionStaysInsideTheFile() throws {
    // Five base lines, three head lines: the last two are deleted with nothing after them.
    let raw = """
      diff --git a/Sources/A.swift b/Sources/A.swift
      --- a/Sources/A.swift
      +++ b/Sources/A.swift
      @@ -1,5 +1,3 @@
       one
       two
       three
      -four
      -five
      """
    let fileDiff = try #require(GitDiffParser().parse(raw).first)
    let map = ChangedLineMap(fileDiff: fileDiff)

    #expect(map.headLine(forBaseLine: 3) == 3)
    #expect(map.headLine(forBaseLine: 4) == 3)
    #expect(map.headLine(forBaseLine: 5) == 3)
    #expect(map.reportLine(for: LineSpan(start: 4, end: 5), at: .base) == 3)
  }

  @Test("a deleted file has no head line to map onto")
  func deletedFileHasNoHeadSide() {
    let map = ChangedLineMap(
      fileDiff: TestSupport.fileDiff(
        path: "Sources/Gone.swift",
        removed: ["func wasHere() {}"],
        isDeleted: true
      )
    )

    #expect(map.headLine(forBaseLine: 1) == nil)
    #expect(map.reportLine(for: LineSpan(line: 1), at: .base) == nil)
  }

  // MARK: - Report line

  @Test("a head finding is reported against the first changed line inside the node")
  func headFindingReportsFirstChangedLine() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.reportLine(for: LineSpan(start: 1, end: 6), at: .head) == 3)
    #expect(map.reportLine(for: LineSpan(start: 4, end: 6), at: .head) == 4)
  }

  @Test("an untouched head node is reported against its own first line")
  func untouchedHeadNodeReportsItsStart() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    #expect(map.reportLine(for: LineSpan(start: 1, end: 2), at: .head) == 1)
  }

  @Test("a base finding is reported against a head line, not a base line")
  func baseFindingIsTranslated() {
    let map = ChangedLineMap(fileDiff: Self.mixedHunkDiff())

    // The node spanned base lines 3 and 4, both deleted: the reader looks at head line 3.
    #expect(map.reportLine(for: LineSpan(start: 3, end: 4), at: .base) == 3)
    // An untouched base node is translated through the change too.
    #expect(map.reportLine(for: LineSpan(line: 5), at: .base) == 6)
  }

  // MARK: - Sides

  @Test("a renamed file keeps one reported path across both sides")
  func renamedFile() {
    let fileDiff = FileDiff(
      oldPath: "Sources/Old.swift",
      newPath: "Sources/New.swift",
      isDeleted: false,
      isAdded: false,
      isRenamed: true,
      hunks: [
        Hunk(
          oldStart: 1,
          newStart: 1,
          lines: [DiffLine(kind: .added, number: 2, text: "let added = 1")]
        )
      ]
    )

    let map = ChangedLineMap(fileDiff: fileDiff)

    #expect(map.path == "Sources/New.swift")
    #expect(map.hasBaseSide)
    #expect(map.hasHeadSide)
    #expect(map.reportLine(for: LineSpan(start: 1, end: 3), at: .head) == 2)
  }

  @Test("an added file has no base side and every head line is new")
  func addedFile() {
    let map = ChangedLineMap(
      fileDiff: TestSupport.fileDiff(
        path: "Sources/New.swift",
        added: ["import Foundation", "func f() {}"],
        isAdded: true
      )
    )

    #expect(map.changedLines(at: .head) == [1, 2])
    #expect(map.changedLines(at: .base).isEmpty)
    #expect(!map.hasBaseSide)
    #expect(map.touches(LineSpan(start: 1, end: 2), at: .head))
    #expect(!map.touches(LineSpan(start: 1, end: 2), at: .base))
  }

  @Test("a map is built from the file diff a rule already holds")
  func builtFromFileDiff() {
    let fileDiff = Self.mixedHunkDiff(path: "Sources/Thing.swift")

    #expect(fileDiff.changedLineMap.path == "Sources/Thing.swift")
    #expect(fileDiff.changedLineMap == ChangedLineMap(fileDiff: fileDiff))
  }

  /// A function declaration whose body opens on the signature line and runs to the span's end,
  /// which is the layout the own-versus-nested rule has to get right.
  private static func function(span: LineSpan) -> SyntaxNode {
    SyntaxNode(
      kind: .functionDecl,
      span: span,
      name: "f",
      children: [SyntaxNode(kind: .codeBlock, span: span)]
    )
  }
}
