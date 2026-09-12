import Testing
@testable import RegressionGuardKit

@Suite("Evidence bundle tests")
struct EvidenceBundleTests {
  @Test("preserves diff-local and optional repository evidence")
  func preservesEvidence() {
    let bundle = Self.makeBundle()

    #expect(bundle.fileDiffs.count == 1)
    #expect(bundle.fileDiffs.first?.displayPath == "Sources/Example.swift")
    #expect(bundle.fileContents["Sources/Example.swift"]?.new == "let answer = 42")
    #expect(bundle.pathEvidence["Sources/Example.swift"]?.isTest == false)
    #expect(bundle.commit.headRef == "HEAD")
    #expect(bundle.repository.coverage == nil)
    #expect(bundle.repository.unavailableSignals == [.coverage, .ciConfiguration])
  }

  @Test("preserves pull-request and repository-wide evidence")
  func preservesRepositoryEvidence() {
    let pullRequest = PullRequestEvidence(
      number: 42,
      title: "Guard coverage",
      body: "Adds repository signals."
    )
    let bundle = EvidenceBundle(
      fileDiffs: [],
      commit: CommitEvidence(
        baseRef: "origin/main",
        headRef: "HEAD",
        messages: [],
        pullRequest: pullRequest
      ),
      repository: RepositoryEvidence(
        coverage: CoverageEvidence(lineCoverage: 91.2, baseLineCoverage: 92.0),
        ciConfiguration: CIConfigurationEvidence(changedPaths: [".github/workflows/ci.yml"]),
        generatedPaths: ["Generated/Output.swift"]
      )
    )

    #expect(bundle.commit.pullRequest?.number == 42)
    #expect(bundle.repository.coverage?.baseLineCoverage == 92.0)
    #expect(bundle.repository.ciConfiguration?.changedPaths.count == 1)
    #expect(bundle.repository.generatedPaths == ["Generated/Output.swift"])
  }

  private static func makeBundle() -> EvidenceBundle {
    let diff = FileDiff(
      oldPath: "Sources/Example.swift",
      newPath: "Sources/Example.swift",
      isDeleted: false,
      isAdded: false,
      isRenamed: false,
      hunks: [
        Hunk(
          oldStart: 1,
          newStart: 1,
          lines: [DiffLine(kind: .added, number: 1, text: "let answer = 42")]
        )
      ]
    )
    return EvidenceBundle(
      fileDiffs: [diff],
      fileContents: [
        "Sources/Example.swift": FileContentEvidence(
          old: "let answer = 41",
          new: "let answer = 42"
        )
      ],
      pathEvidence: [
        "Sources/Example.swift": PathEvidence(
          isTest: false,
          isIgnored: false,
          isGenerated: false
        )
      ],
      commit: CommitEvidence(
        baseRef: "origin/main",
        headRef: "HEAD",
        messages: ["fix answer"]
      ),
      repository: RepositoryEvidence(unavailableSignals: [.coverage, .ciConfiguration])
    )
  }
}
