import Foundation
import Testing
@testable import RegressionGuardKit

/// Records what it was asked for, so a test can assert the runner batches base-ref reads.
private final class RecordingProvider: SyntacticEvidenceProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [[SyntacticEvidenceRequest]] = []
  private let evidence: SyntacticEvidence

  init(evidence: SyntacticEvidence = .none) {
    self.evidence = evidence
  }

  var callCount: Int { lock.withLock { calls.count } }
  var requestedPaths: [String] { lock.withLock { calls.flatMap { $0.map(\.path) } } }

  func syntacticEvidence(for requests: [SyntacticEvidenceRequest]) -> SyntacticEvidence {
    lock.withLock { calls.append(requests) }
    return evidence
  }
}

/// Declares that it needs trees, and reports what it actually received.
private struct SyntaxDemandingRule: Rule {
  static let ruleID = "syntax_demanding"
  static let defaultSeverity = Severity.warning
  static let requiresSyntacticEvidence = true

  func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] { [] }

  func evaluate(evidence: EvidenceBundle, context: RuleContext) -> [Violation] {
    evidence.fileDiffs.map { fileDiff in
      let syntax = evidence.syntax.evidence(for: fileDiff)
      let state: String
      switch syntax {
      case nil: state = "not-requested"
      case let file? where file.isDegraded: state = "degraded"
      case let file?: state = "parsed:\(file.headTree?.lineCount ?? 0)"
      }
      return Violation(
        ruleID: Self.ruleID,
        severity: Self.defaultSeverity,
        file: fileDiff.displayPath,
        message: state
      )
    }
  }
}

/// Declares no need for trees, so the runner must not parse on its behalf.
private struct LineOnlyRule: Rule {
  static let ruleID = "line_only"
  static let defaultSeverity = Severity.warning

  func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] { [] }
}

@Suite("Syntactic evidence wiring tests")
struct SyntacticEvidenceEngineTests {
  @Test("a rule that declares no need for trees causes no parsing")
  func lineOnlyRuleRequestsNothing() {
    let provider = RecordingProvider()
    let engine = RuleEngine(rules: [LineOnlyRule()], syntacticEvidenceProvider: provider)

    _ = engine.evaluate(evidence: Self.bundle(), context: TestSupport.context())

    #expect(provider.callCount == 0)
  }

  @Test("every requested file is fetched in a single batched call")
  func requestsAreBatchedIntoOneCall() {
    let provider = RecordingProvider()
    let engine = RuleEngine(
      rules: [SyntaxDemandingRule(), SyntaxDemandingRule()],
      syntacticEvidenceProvider: provider
    )
    let bundle = Self.bundle(
      paths: ["Sources/A.swift", "Sources/B.swift", "README.md"]
    )

    _ = engine.evaluate(evidence: bundle, context: TestSupport.context())

    #expect(provider.callCount == 1)
    #expect(provider.requestedPaths == ["Sources/A.swift", "Sources/B.swift"])
  }

  @Test("a rule receives the base and head trees resolved for its file")
  func ruleReceivesResolvedTrees() {
    let provider = RecordingProvider(
      evidence: SyntacticEvidence(
        files: [
          SyntacticFileEvidence(
            path: "Sources/A.swift",
            base: .parsed(Self.tree(path: "Sources/A.swift", ref: "base")),
            head: .parsed(Self.tree(path: "Sources/A.swift", ref: "head"))
          )
        ]
      )
    )
    let engine = RuleEngine(rules: [SyntaxDemandingRule()], syntacticEvidenceProvider: provider)

    let result = engine.evaluate(
      evidence: Self.bundle(paths: ["Sources/A.swift"]),
      context: TestSupport.context()
    )

    #expect(result.violations.map(\.message) == ["parsed:2"])
    #expect(result.syntacticEvidenceGaps.isEmpty)
  }

  @Test("a run without a parser degrades explicitly instead of passing silently")
  func missingParserDegradesExplicitly() {
    let engine = RuleEngine(rules: [SyntaxDemandingRule()], syntacticEvidenceProvider: nil)

    let result = engine.evaluate(
      evidence: Self.bundle(paths: ["Sources/A.swift"]),
      context: TestSupport.context()
    )

    #expect(result.violations.map(\.message) == ["degraded"])
    #expect(result.syntacticEvidenceGaps.map(\.reason) == [.parserUnavailable, .parserUnavailable])
    #expect(result.syntacticEvidenceGaps.allSatisfy { $0.path == "Sources/A.swift" })
  }

  @Test("an unresolvable base ref is reported as a gap, not an absence")
  func unreadableBaseRefIsAGap() {
    let provider = RecordingProvider(
      evidence: SyntacticEvidence(
        files: [
          SyntacticFileEvidence(
            path: "Sources/A.swift",
            base: .unavailable(.sourceReadFailed, detail: "fatal: bad object"),
            head: .parsed(Self.tree(path: "Sources/A.swift", ref: "head"))
          )
        ]
      )
    )
    let engine = RuleEngine(rules: [SyntaxDemandingRule()], syntacticEvidenceProvider: provider)

    let result = engine.evaluate(
      evidence: Self.bundle(paths: ["Sources/A.swift"]),
      context: TestSupport.context()
    )

    #expect(result.violations.map(\.message) == ["degraded"])
    #expect(result.syntacticEvidenceGaps.map(\.ref) == [.base])
    #expect(result.syntacticEvidenceGaps.first?.detail == "fatal: bad object")
  }

  @Test("evidence supplied by the caller is used as-is and nothing is parsed")
  func preresolvedEvidenceIsNotRefetched() {
    let provider = RecordingProvider()
    let engine = RuleEngine(rules: [SyntaxDemandingRule()], syntacticEvidenceProvider: provider)
    let bundle = Self.bundle(paths: ["Sources/A.swift"])
      .withSyntacticEvidence(
        SyntacticEvidence(
          files: [
            SyntacticFileEvidence(
              path: "Sources/A.swift",
              base: .absent(.fileAdded),
              head: .parsed(Self.tree(path: "Sources/A.swift", ref: "head"))
            )
          ]
        )
      )

    let result = engine.evaluate(evidence: bundle, context: TestSupport.context())

    #expect(provider.callCount == 0)
    #expect(result.violations.map(\.message) == ["parsed:2"])
  }

  @Test("ignored paths are neither parsed nor shown to an ordinary rule")
  func ignoredPathsAreNotParsed() {
    let provider = RecordingProvider()
    let engine = RuleEngine(rules: [SyntaxDemandingRule()], syntacticEvidenceProvider: provider)

    _ = engine.evaluate(
      evidence: Self.bundle(paths: ["Sources/A.swift", "Generated/B.swift"]),
      context: TestSupport.context()
    )

    #expect(provider.requestedPaths == ["Sources/A.swift"])
  }

  @Test("an approved change parses nothing")
  func approvedChangeParsesNothing() {
    let provider = RecordingProvider()
    let engine = RuleEngine(rules: [SyntaxDemandingRule()], syntacticEvidenceProvider: provider)

    let result = engine.evaluate(
      evidence: Self.bundle(paths: ["Sources/A.swift"]),
      context: TestSupport.context(commitMessages: ["fix: regression-guard:approve"])
    )

    #expect(provider.callCount == 0)
    #expect(result.violations.isEmpty)
    #expect(result.syntacticEvidenceGaps.isEmpty)
  }

  @Test("only Swift sources are requested")
  func onlySwiftSourcesAreRequested() {
    let rule = SyntaxDemandingRule()

    #expect(
      rule.syntacticEvidenceRequests(
        for: TestSupport.fileDiff(path: "Sources/A.swift", added: ["let a = 1"])
      ).map(\.path) == ["Sources/A.swift"]
    )
    #expect(
      rule.syntacticEvidenceRequests(
        for: TestSupport.fileDiff(path: ".github/workflows/ci.yml", added: ["run: true"])
      ).isEmpty
    )
    #expect(
      LineOnlyRule().syntacticEvidenceRequests(
        for: TestSupport.fileDiff(path: "Sources/A.swift", added: ["let a = 1"])
      ).isEmpty
    )
  }

  @Test("the default rule set still reports violations through the evidence result")
  func defaultRuleSetReportsThroughResult() {
    let engine = RuleEngine()
    let bundle = EvidenceBundle(
      fileDiffs: [
        TestSupport.fileDiff(
          path: "Tests/ExampleTests.swift",
          removed: ["  func testAnswer() {}"],
          isDeleted: true
        )
      ],
      commit: CommitEvidence(baseRef: "base", headRef: "head", messages: [])
    )

    let result = engine.evaluate(evidence: bundle, context: TestSupport.context())

    #expect(result.violations.contains { $0.ruleID == "disabled_or_skipped_test" })
    #expect(result.syntacticEvidenceGaps.isEmpty)
  }

  private static func bundle(paths: [String] = ["Sources/A.swift"]) -> EvidenceBundle {
    EvidenceBundle(
      fileDiffs: paths.map { TestSupport.fileDiff(path: $0, added: ["let answer = 42"]) },
      commit: CommitEvidence(baseRef: "base", headRef: "head", messages: [])
    )
  }

  private static func tree(path: String, ref: String) -> SyntaxTree {
    SyntaxTree(
      path: path,
      ref: ref,
      root: SyntaxNode(kind: .sourceFile, span: LineSpan(start: 1, end: 2)),
      lineCount: 2
    )
  }
}
