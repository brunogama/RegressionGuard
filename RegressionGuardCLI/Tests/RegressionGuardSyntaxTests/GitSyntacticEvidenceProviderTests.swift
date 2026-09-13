import Foundation
import RegressionGuardKit
import RegressionGuardSyntax
import Testing

/// The provider reading real objects out of a real repository.
///
/// A class rather than a struct so `deinit` removes the repository; Swift Testing builds one
/// instance per test, so every case gets a repository of its own.
///
/// `Sendable` because a synchronous test case reaches its suite from a nonisolated context, and
/// the conformance is checked rather than asserted: the only stored property is a `URL`. Swift
/// 6.0 rejects the suite without it and newer compilers do not, so this failed only in CI.
@Suite("Git syntactic evidence provider tests")
final class GitSyntacticEvidenceProviderTests: Sendable {

  private let repositoryURL: URL

  init() async throws {
    repositoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString
    )
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
    try await git(["init", "-q", "-b", "main"])
    try await git(["config", "user.email", "test@example.com"])
    try await git(["config", "user.name", "Regression Guard Tests"])
  }

  deinit {
    try? FileManager.default.removeItem(at: repositoryURL)
  }

  @Test("parses both sides of a changed file")
  func parsesBothSides() async throws {
    try write("func total() -> Int { 1 }\n", to: "Sources/Total.swift")
    let base = try await commit("Add total")
    try write("func total() -> Int { 2 }\n", to: "Sources/Total.swift")
    let head = try await commit("Change total")

    let evidence = provider(base: base, head: head)
      .syntacticEvidence(for: [
        SyntacticEvidenceRequest(
          path: "Sources/Total.swift",
          basePath: "Sources/Total.swift",
          headPath: "Sources/Total.swift"
        )
      ])
    let file = try #require(evidence.evidence(for: "Sources/Total.swift"))

    #expect(file.gaps.isEmpty)
    #expect(file.baseTree?.firstNode(ofKind: .integerLiteralExpr)?.name == "1")
    #expect(file.headTree?.firstNode(ofKind: .integerLiteralExpr)?.name == "2")
    #expect(file.baseTree?.ref == base)
  }

  @Test("a side the change never had is an absence, not a gap")
  func absentSidesAreNotGaps() async throws {
    try write("let existing = 1\n", to: "Sources/Existing.swift")
    let base = try await commit("Add existing")
    try write("func added() {}\n", to: "Sources/Added.swift")
    let head = try await commit("Add a file")

    let evidence = provider(base: base, head: head)
      .syntacticEvidence(for: [
        SyntacticEvidenceRequest(
          path: "Sources/Added.swift",
          basePath: nil,
          headPath: "Sources/Added.swift"
        )
      ])
    let file = try #require(evidence.evidence(for: "Sources/Added.swift"))

    #expect(file.base == .absent(.fileAdded))
    #expect(file.gaps.isEmpty)
    #expect(file.headTree != nil)
  }

  @Test("source that was expected and could not be read is a gap naming the ref")
  func unreadableSourceIsAGap() async throws {
    try write("func total() -> Int { 1 }\n", to: "Sources/Total.swift")
    let head = try await commit("Add total")

    // The request claims a base side the repository does not have, which is what an unreachable
    // base ref looks like from here: source that should have existed and did not arrive.
    let evidence = provider(base: "0000000000000000000000000000000000000000", head: head)
      .syntacticEvidence(for: [
        SyntacticEvidenceRequest(
          path: "Sources/Total.swift",
          basePath: "Sources/Total.swift",
          headPath: "Sources/Total.swift"
        )
      ])
    let file = try #require(evidence.evidence(for: "Sources/Total.swift"))
    let gap = try #require(file.gaps.first)

    #expect(file.gaps.count == 1)
    #expect(gap.ref == .base)
    #expect(gap.reason == .sourceReadFailed)
    #expect(gap.detail?.contains("Sources/Total.swift") == true)
    #expect(file.headTree != nil, "one unreadable side must not cost the other")
  }

  @Test("reads head from the working tree, including a file never committed")
  func readsTheWorkingTree() async throws {
    try write("func total() -> Int { 1 }\n", to: "Sources/Total.swift")
    let base = try await commit("Add total")
    try write("func total() -> Int { 2 }\n", to: "Sources/Total.swift")

    let evidence = provider(base: base, head: nil)
      .syntacticEvidence(for: [
        SyntacticEvidenceRequest(
          path: "Sources/Total.swift",
          basePath: "Sources/Total.swift",
          headPath: "Sources/Total.swift"
        )
      ])
    let file = try #require(evidence.evidence(for: "Sources/Total.swift"))

    #expect(file.gaps.isEmpty)
    #expect(
      file.headTree?.firstNode(ofKind: .integerLiteralExpr)?.name == "2",
      "head must be the checkout"
    )
    #expect(file.headTree?.ref == "working-tree")
  }

  @Test("names its own grammar, so an under-selected series is visible")
  func namesItsGrammar() {
    #expect(provider(base: "HEAD", head: nil).grammar == CompiledSyntaxGrammar.current)
  }

  // MARK: - Repository

  private func provider(base: String, head: String?) -> GitSyntacticEvidenceProvider {
    GitSyntacticEvidenceProvider(
      repositoryDirectory: repositoryURL,
      baseRef: base,
      headRef: head
    )
  }

  @discardableResult
  private func git(_ arguments: [String]) async throws -> String {
    try await GitRepository(workingDirectory: repositoryURL).run(arguments)
  }

  private func write(_ contents: String, to relativePath: String) throws {
    let url = repositoryURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func commit(_ message: String) async throws -> String {
    try await git(["add", "."])
    try await git(["commit", "-q", "-m", message])
    return try await git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
