import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Syntactic evidence tests")
struct SyntacticEvidenceTests {
  @Test("base and head trees arrive together for a modified file")
  func pairsBaseAndHead() {
    let evidence = SyntacticEvidence(
      files: [
        SyntacticFileEvidence(
          path: "Sources/Example.swift",
          base: .parsed(Self.tree(path: "Sources/Example.swift", ref: "origin/main")),
          head: .parsed(Self.tree(path: "Sources/Example.swift", ref: "HEAD"))
        )
      ]
    )

    let file = evidence.evidence(for: "Sources/Example.swift")
    #expect(file?.baseTree?.ref == "origin/main")
    #expect(file?.headTree?.ref == "HEAD")
    #expect(file?.isDegraded == false)
    #expect(file?.gaps.isEmpty == true)
  }

  @Test("a file no rule asked about is distinguishable from one with no trees")
  func unrequestedFileIsDistinctFromUnavailable() {
    let evidence = SyntacticEvidence(
      files: [
        SyntacticFileEvidence(
          path: "Sources/Requested.swift",
          base: .unavailable(.sourceReadFailed, detail: "bad object"),
          head: .unavailable(.sourceReadFailed, detail: "bad object")
        )
      ]
    )

    #expect(evidence.evidence(for: "Sources/Never.swift") == nil)
    let requested = evidence.evidence(for: "Sources/Requested.swift")
    #expect(requested != nil)
    #expect(requested?.baseTree == nil)
    #expect(requested?.isDegraded == true)
  }

  @Test("an added file has an explicit base absence rather than a gap")
  func addedFileAbsenceIsNotAGap() {
    let file = SyntacticFileEvidence(
      path: "Sources/New.swift",
      base: .absent(.fileAdded),
      head: .parsed(Self.tree(path: "Sources/New.swift", ref: "HEAD"))
    )

    #expect(file.base == .absent(.fileAdded))
    #expect(file.isDegraded == false)
    #expect(file.gaps.isEmpty)
  }

  @Test("a deleted file has an explicit head absence rather than a gap")
  func deletedFileAbsenceIsNotAGap() {
    let file = SyntacticFileEvidence(
      path: "Sources/Gone.swift",
      base: .parsed(Self.tree(path: "Sources/Gone.swift", ref: "origin/main")),
      head: .absent(.fileDeleted)
    )

    #expect(file.head == .absent(.fileDeleted))
    #expect(file.isDegraded == false)
    #expect(file.baseTree != nil)
  }

  @Test("each unavailable side becomes one reportable gap")
  func unavailableSidesBecomeGaps() {
    let evidence = SyntacticEvidence(
      files: [
        SyntacticFileEvidence(
          path: "Sources/B.swift",
          base: .unavailable(.sourceReadFailed, detail: "fatal: bad object"),
          head: .parsed(Self.tree(path: "Sources/B.swift", ref: "HEAD"))
        ),
        SyntacticFileEvidence(
          path: "Sources/A.swift",
          base: .unavailable(.parserUnavailable, detail: nil),
          head: .unavailable(.parserUnavailable, detail: nil)
        ),
      ]
    )

    #expect(
      evidence.gaps == [
        SyntaxEvidenceGap(path: "Sources/A.swift", ref: .base, reason: .parserUnavailable),
        SyntaxEvidenceGap(path: "Sources/A.swift", ref: .head, reason: .parserUnavailable),
        SyntaxEvidenceGap(
          path: "Sources/B.swift",
          ref: .base,
          reason: .sourceReadFailed,
          detail: "fatal: bad object"
        ),
      ]
    )
  }

  @Test("an ill-formed parse is still a tree, not a gap")
  func recoveredParseIsNotAGap() {
    let file = SyntacticFileEvidence(
      path: "Sources/Broken.swift",
      base: .parsed(Self.tree(path: "Sources/Broken.swift", ref: "origin/main")),
      head: .parsed(
        SyntaxTree(
          path: "Sources/Broken.swift",
          ref: "HEAD",
          root: SyntaxNode(kind: .sourceFile, span: LineSpan(line: 1)),
          lineCount: 1,
          hasParseErrors: true
        )
      )
    )

    #expect(file.isDegraded == false)
    #expect(file.headTree?.hasParseErrors == true)
  }

  @Test("requests encode the expected absences of added, deleted, and renamed files")
  func requestsEncodeAbsences() {
    let added = SyntacticEvidenceRequest(
      fileDiff: TestSupport.fileDiff(path: "Sources/New.swift", added: ["let a = 1"], isAdded: true)
    )
    #expect(added.basePath == nil)
    #expect(added.headPath == "Sources/New.swift")

    let deleted = SyntacticEvidenceRequest(
      fileDiff: TestSupport.fileDiff(
        path: "Sources/Gone.swift",
        removed: ["let a = 1"],
        isDeleted: true
      )
    )
    #expect(deleted.basePath == "Sources/Gone.swift")
    #expect(deleted.headPath == nil)
    #expect(deleted.path == "Sources/Gone.swift")

    let renamed = SyntacticEvidenceRequest(
      fileDiff: FileDiff(
        oldPath: "Sources/Old.swift",
        newPath: "Sources/New.swift",
        isDeleted: false,
        isAdded: false,
        isRenamed: true,
        hunks: []
      )
    )
    #expect(renamed.path == "Sources/New.swift")
    #expect(renamed.basePath == "Sources/Old.swift")
    #expect(renamed.headPath == "Sources/New.swift")
  }

  @Test("a run without a parser reports every requested side as a gap")
  func missingParserReportsGaps() {
    let requests = [
      SyntacticEvidenceRequest(
        path: "Sources/Example.swift",
        basePath: "Sources/Example.swift",
        headPath: "Sources/Example.swift"
      ),
      SyntacticEvidenceRequest(
        path: "Sources/New.swift",
        basePath: nil,
        headPath: "Sources/New.swift"
      ),
    ]

    let evidence = UnavailableSyntacticEvidenceProvider().syntacticEvidence(for: requests)

    #expect(evidence.gaps.count == 3)
    #expect(evidence.gaps.allSatisfy { $0.reason == .parserUnavailable })
    #expect(evidence.evidence(for: "Sources/New.swift")?.base == .absent(.fileAdded))
    #expect(evidence.evidence(for: "Sources/Example.swift")?.isDegraded == true)
  }

  @Test("evidence can be narrowed to the paths a rule is allowed to see")
  func retainingPaths() {
    let evidence = SyntacticEvidence(
      files: [
        SyntacticFileEvidence(
          path: "Sources/Kept.swift",
          base: .absent(.fileAdded),
          head: .parsed(Self.tree(path: "Sources/Kept.swift", ref: "HEAD"))
        ),
        SyntacticFileEvidence(
          path: "Generated/Dropped.swift",
          base: .absent(.fileAdded),
          head: .parsed(Self.tree(path: "Generated/Dropped.swift", ref: "HEAD"))
        ),
      ]
    )

    let narrowed = evidence.retainingPaths(["Sources/Kept.swift"])

    #expect(narrowed.files.map(\.path) == ["Sources/Kept.swift"])
    #expect(narrowed.evidence(for: "Generated/Dropped.swift") == nil)
  }

  @Test("evidence round-trips through Codable so a report can carry it")
  func evidenceRoundTripsThroughCodable() throws {
    let evidence = SyntacticEvidence(
      files: [
        SyntacticFileEvidence(
          path: "Sources/Example.swift",
          base: .unavailable(.sourceNotDecodable, detail: "not utf-8"),
          head: .parsed(Self.tree(path: "Sources/Example.swift", ref: "HEAD"))
        )
      ]
    )

    let data = try JSONEncoder().encode(evidence)
    let decoded = try JSONDecoder().decode(SyntacticEvidence.self, from: data)

    #expect(decoded == evidence)
    #expect(SyntacticEvidence.none.isEmpty)
  }

  private static func tree(path: String, ref: String) -> SyntaxTree {
    SyntaxTree(
      path: path,
      ref: ref,
      root: SyntaxNode(
        kind: .sourceFile,
        span: LineSpan(start: 1, end: 2),
        children: [
          SyntaxNode(kind: .variableDecl, span: LineSpan(line: 2), name: "answer")
        ]
      ),
      lineCount: 2
    )
  }
}
