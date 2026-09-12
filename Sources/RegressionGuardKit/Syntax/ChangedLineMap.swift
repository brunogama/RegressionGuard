import Foundation

/// The lines one file's change touched, on each side, and the translation between the two.
///
/// This is the bridge between two different coordinate systems. A violation carries a line number
/// a reader opens in the head file; a syntax node carries an absolute position in whichever whole
/// file it was parsed from. Rules ask this map both questions they cannot answer from a tree
/// alone: whether a node is inside the change rather than merely inside the file, and which head
/// line a finding belongs on.
///
/// Physical lines throughout, matching `LineSpan`. A `#sourceLocation` directive makes a file's
/// presumed lines disagree with the lines a diff talks about, so the parsing side must report
/// `SourceLocation.line` and never `presumedLine`; a presumed line could name a line that does
/// not exist in the diff at all.
public struct ChangedLineMap: Equatable, Sendable {
  /// The path a finding is reported against, matching `FileDiff.displayPath`.
  public let path: String
  /// Head-side line numbers the change added.
  public let addedLines: Set<Int>
  /// Base-side line numbers the change removed.
  public let removedLines: Set<Int>
  /// `false` when the file was deleted, so no base line has a head line to land on.
  public let hasHeadSide: Bool
  /// `false` when the file was added, so there are no base lines at all.
  public let hasBaseSide: Bool

  /// Head line for each base line named by a hunk, including the deleted ones: a removed line
  /// maps to the head line its deletion left behind.
  private let headLineByBaseLine: [Int: Int]
  /// For base lines no hunk names, the net line delta of the hunks that precede them, in
  /// ascending order.
  private let deltasAfterHunks: [HunkDelta]

  /// The net line shift one hunk leaves behind, applying to every base line after it.
  private struct HunkDelta: Equatable, Sendable {
    let firstBaseLineAfter: Int
    let delta: Int
  }

  public init(fileDiff: FileDiff) {
    path = fileDiff.displayPath
    addedLines = Set(fileDiff.addedLines.map(\.number))
    removedLines = Set(fileDiff.removedLines.map(\.number))
    hasHeadSide = !fileDiff.isDeleted
    hasBaseSide = !fileDiff.isAdded

    var headLines: [Int: Int] = [:]
    var deletionAnchors: [Int: Int] = [:]
    var deltas: [HunkDelta] = []
    var lastLineTheDiffNames = 0
    for hunk in fileDiff.hunks {
      var baseLine = hunk.oldStart
      var headLine = hunk.newStart
      for line in hunk.lines {
        switch line.kind {
        case .context:
          headLines[baseLine] = headLine
          lastLineTheDiffNames = max(lastLineTheDiffNames, headLine)
          baseLine += 1
          headLine += 1
        case .added:
          lastLineTheDiffNames = max(lastLineTheDiffNames, headLine)
          headLine += 1
        case .removed:
          // No head line of its own: the finding lands where the deleted content used to be,
          // which is the next surviving line - clamped below, since a deletion running to the
          // end of the file leaves nothing after it to point at.
          deletionAnchors[baseLine] = max(1, headLine)
          baseLine += 1
        }
      }
      deltas.append(HunkDelta(firstBaseLineAfter: baseLine, delta: headLine - baseLine))
    }
    for (baseLine, anchor) in deletionAnchors {
      headLines[baseLine] = min(anchor, max(1, lastLineTheDiffNames))
    }
    headLineByBaseLine = headLines
    deltasAfterHunks = deltas.sorted { $0.firstBaseLineAfter < $1.firstBaseLineAfter }
  }

  /// The lines the change touched on one side, in that side's own numbering.
  public func changedLines(at ref: SyntaxRef) -> Set<Int> {
    switch ref {
    case .base: return removedLines
    case .head: return addedLines
    }
  }

  /// - Returns: `true` when the change touched a line inside `span` on `ref`'s side.
  public func touches(_ span: LineSpan, at ref: SyntaxRef) -> Bool {
    changedLines(at: ref).contains { span.contains(line: $0) }
  }

  /// - Returns: the changed lines inside `span` on `ref`'s side, in source order.
  public func changedLines(in span: LineSpan, at ref: SyntaxRef) -> [Int] {
    changedLines(at: ref).filter { span.contains(line: $0) }.sorted()
  }

  /// Where the change falls relative to `node`, which is what a rule needs to tell an edited
  /// declaration from an untouched declaration whose body was edited.
  public func changeScope(of node: SyntaxNode, at ref: SyntaxRef) -> NodeChangeScope {
    guard touches(node.span, at: ref) else { return .outside }
    let own = node.ownLines
    return changedLines(at: ref).contains(where: own.contains) ? .own : .nested
  }

  /// The nodes of `kind` in `tree` that the change actually reached, in source order.
  ///
  /// `ref` has to name the side `tree` was parsed from. Nothing here can check that: a
  /// `SyntaxTree`'s `ref` is the free-form ref it was read at, not which side of the comparison
  /// it is, so a head tree queried with `.base` lines would quietly return the wrong nodes.
  public func changedNodes(
    ofKind kind: SyntaxNodeKind,
    in tree: SyntaxTree,
    at ref: SyntaxRef
  ) -> [SyntaxNode] {
    tree.nodes(ofKind: kind).filter { touches($0.span, at: ref) }
  }

  /// The head line a base line lands on.
  ///
  /// A surviving line maps to wherever the change moved it. A deleted line has no head line of
  /// its own and maps to the line its deletion left behind, so a finding on code that is gone
  /// still points at the place a reader can see it went missing. A deletion that runs to the end
  /// of the file has nothing after it, so it lands on the last line the diff names rather than
  /// one line past the end of a file the reader cannot open there.
  ///
  /// - Returns: `nil` when the file has no head side at all, which is the honest answer for a
  ///   deleted file; `Violation.line` is optional for exactly this case.
  public func headLine(forBaseLine line: Int) -> Int? {
    guard hasHeadSide else { return nil }
    if let mapped = headLineByBaseLine[line] { return mapped }
    let delta = deltasAfterHunks.last { $0.firstBaseLineAfter <= line }?.delta ?? 0
    return max(1, line + delta)
  }

  /// The head-file line a finding on `span` should be reported against.
  ///
  /// The first changed line inside the span, so a finding on a large node points at the edit
  /// rather than at the declaration that happens to enclose it. A span the change never touched
  /// falls back to its own first line. Base spans are translated through the change, because a
  /// base line number shown as if it were a head line sends the reader to unrelated code.
  public func reportLine(for span: LineSpan, at ref: SyntaxRef) -> Int? {
    let anchor = changedLines(in: span, at: ref).first ?? span.start
    switch ref {
    case .head: return anchor
    case .base: return headLine(forBaseLine: anchor)
    }
  }
}
