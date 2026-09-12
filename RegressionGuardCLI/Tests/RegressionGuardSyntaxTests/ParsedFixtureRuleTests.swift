import Foundation
import RegressionGuardKit
import RegressionGuardSyntax
import Testing

/// What a rule test looks like once rules consume parsed source.
///
/// The rule suites in the root package hand-build `SyntaxTree` values through `SyntaxFixture`,
/// because RegressionGuardKit has no parser and its test target cannot be given one. That buys
/// fast tests that state an edge case outright, and costs exactly one thing: the fixture decides
/// what the projection looks like. A rule can pass against a node shape swift-syntax never emits,
/// and nothing fails when it does - the detection simply stops firing.
///
/// This suite is the other end of that trade, and only this package can hold it. A fixture is a
/// pair of real Swift sources; they are committed to a scratch repository as base and head, the
/// diff comes from `git`, the trees come from `SwiftSyntaxProjection`, and the rule runs through
/// `RegressionGuardRunner` the way the CLI runs it. Nothing is hand-shaped, so it answers the
/// question the hand-built fixtures cannot: does the detection fire on what the parser produces?
///
/// A class rather than a struct so `deinit` removes the repository; Swift Testing builds one
/// instance per test, so every case gets a repository of its own.
@Suite("Parsed fixture rule tests")
final class ParsedFixtureRuleTests {

  /// A fixture pair: one file, two versions, written as the source a reviewer would read.
  ///
  /// No hunks. Stating a change as two whole files and letting `git` compute the difference is
  /// what keeps the fixture honest about line numbers - `TestSupport.fileDiff` synthesizes them
  /// from 1, so a rule that reports the wrong line still passes there.
  struct SourcePair {
    let path: String
    let base: String
    let head: String
  }

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

  // MARK: - Tests

  @Test("catches a tautology the text matchers let through, on real parsed source")
  func catchesATautologyOnlyTheTreeSees() async throws {
    let result = try await evaluate(Self.tautologyRewrite)

    #expect(result.syntacticEvidenceGaps.isEmpty, "gaps: \(result.syntacticEvidenceGaps)")
    let violation = try #require(
      result.violations.first { $0.ruleID == "weakened_assertion" },
      "no weakened_assertion finding in \(result.violations)"
    )
    #expect(violation.evidence == .syntax)
    #expect(violation.line == 5)
    #expect(result.syntaxGrammar == CompiledSyntaxGrammar.current)
  }

  /// The same pair with no parser, which is what the text matchers actually catch.
  ///
  /// `XCTAssertEqual(42, 42)` is not one of the five spellings the fallback knows, so the finding
  /// is lost - and that is the point of asserting it. The run says so rather than reading clean:
  /// the file comes back as a gap on both sides. A silent pass here is the failure this whole
  /// evidence model exists to prevent.
  @Test("without a parser the same change is missed, and the run says so")
  func degradesVisiblyWithoutAParser() async throws {
    let result = try await evaluate(Self.tautologyRewrite, parsed: false)

    #expect(!result.violations.contains { $0.ruleID == "weakened_assertion" })
    #expect(
      result.syntacticEvidenceGaps.allSatisfy { $0.reason == .parserUnavailable },
      "expected parserUnavailable gaps, got \(result.syntacticEvidenceGaps)"
    )
    #expect(
      Set(result.syntacticEvidenceGaps.map(\.ref)) == [.base, .head],
      "both sides were expected and neither arrived"
    )
  }

  @Test("leaves an assertion that still reads the code under test alone")
  func leavesARealAssertionAlone() async throws {
    let result = try await evaluate(
      SourcePair(
        path: Self.tautologyRewrite.path,
        base: Self.tautologyRewrite.base,
        head: Self.source(assertion: "XCTAssertEqual(sut.total, 43)")
      )
    )

    #expect(!result.violations.contains { $0.ruleID == "weakened_assertion" })
  }

  /// Every family that reads a tree, each against source a parser really produced.
  ///
  /// Grouped because they share one failure mode, and it is the reason this suite exists: a
  /// detection that does not survive the real projection does not fail, it goes quiet, and the
  /// hand-built fixtures still pass. The three AST-only families - `known_issue_suppression`,
  /// `implementation_stubbed`, `unreachable_assertion` - have no text fallback at all, so for them
  /// quiet means nothing is found anywhere; the other three would silently fall back to the
  /// matchers the tree was supposed to replace, which is why each case asserts `.syntax` rather
  /// than only that something was reported.
  @Test(
    "every tree-reading family fires on parsed source",
    arguments: [
      Self.knownIssueSuppression,
      Self.stubbedImplementation,
      Self.strandedAssertion,
      Self.skippedTest,
      Self.deletedBranches,
      Self.discardedError,
    ]
  )
  func everyFamilyFiresOnParsedSource(expectation: RuleExpectation) async throws {
    let result = try await evaluate(expectation.pair)

    let violation = try #require(
      result.violations.first { $0.ruleID == expectation.ruleID },
      "no \(expectation.ruleID) finding in \(result.violations)"
    )
    #expect(violation.evidence == .syntax)
  }

  /// A fixture pair and the family it is meant to trip.
  struct RuleExpectation: Sendable {
    let ruleID: String
    let pair: SourcePair
  }

  // MARK: - Fixtures

  /// An agent given a failing assertion replaces its operands with constants.
  ///
  /// Chosen because the line path cannot see it: `WeakenedAssertionRule` matches five literal
  /// tautology spellings, and `XCTAssertEqual(42, 42)` is not among them. The tree answers the
  /// question the text approximates - are the arguments all constants - so the fixture separates
  /// the two paths instead of testing something both would catch.
  private static let tautologyRewrite = SourcePair(
    path: "Tests/TotalTests.swift",
    base: source(assertion: "XCTAssertEqual(sut.total, 42)"),
    head: source(assertion: "XCTAssertEqual(42, 42)")
  )

  /// An agent absorbs a failing test's failure instead of fixing what it caught.
  private static let knownIssueSuppression = RuleExpectation(
    ruleID: "known_issue_suppression",
    pair: SourcePair(
      path: "Tests/TotalTests.swift",
      base: """
        import Testing

        struct TotalTests {
          @Test func total() {
            #expect(sut.total == 42)
          }
        }

        """,
      head: """
        import Testing

        struct TotalTests {
          @Test func total() {
            withKnownIssue {
              #expect(sut.total == 42)
            }
          }
        }

        """
    )
  )

  /// An agent replaces a working implementation with a trap, in production code rather than tests.
  private static let stubbedImplementation = RuleExpectation(
    ruleID: "implementation_stubbed",
    pair: SourcePair(
      path: "Sources/Calculator.swift",
      base: """
        struct Calculator {
          func total(of values: [Int]) -> Int {
            values.reduce(0, +)
          }
        }

        """,
      head: """
        struct Calculator {
          func total(of values: [Int]) -> Int {
            fatalError("not implemented")
          }
        }

        """
    )
  )

  /// An agent strands an assertion behind a branch that never runs rather than deleting it, which
  /// reads as a test that still checks something.
  ///
  /// Written as `if false` after the first attempt - `return` on its own line, then the assertion -
  /// turned out not to strand anything: SwiftParser reads the two lines as one `return
  /// XCTAssertEqual(...)`, so the rule was right to report nothing. A hand-built tree would have
  /// accepted the intended reading and the test would have asserted a behaviour Swift does not
  /// have.
  private static let strandedAssertion = RuleExpectation(
    ruleID: "unreachable_assertion",
    pair: SourcePair(
      path: "Tests/TotalTests.swift",
      base: """
        import XCTest

        final class TotalTests: XCTestCase {
          func testTotal() {
            XCTAssertEqual(sut.total, 42)
          }
        }

        """,
      head: """
        import XCTest

        final class TotalTests: XCTestCase {
          func testTotal() {
            if false {
              XCTAssertEqual(sut.total, 42)
            }
          }
        }

        """
    )
  )

  /// An agent switches a failing test off with a trait rather than fixing what it caught.
  ///
  /// Written as `@Test(.disabled)` because that is the shape with no line-path equivalent: the
  /// trait is a node inside the attribute, and the text matcher has no concept of a whole suite or
  /// a trait spread over several lines.
  private static let skippedTest = RuleExpectation(
    ruleID: "disabled_or_skipped_test",
    pair: SourcePair(
      path: "Tests/TotalTests.swift",
      base: """
        import Testing

        struct TotalTests {
          @Test func total() {
            #expect(sut.total == 42)
          }
        }

        """,
      head: """
        import Testing

        struct TotalTests {
          @Test(.disabled) func total() {
            #expect(sut.total == 42)
          }
        }

        """
    )
  )

  /// An agent deletes the branches a production function was built from.
  ///
  /// Four removed against one survivor, which clears the rule's threshold of three and is a net
  /// removal rather than a reformatting.
  private static let deletedBranches = RuleExpectation(
    ruleID: "behavior_deletion",
    pair: SourcePair(
      path: "Sources/Total.swift",
      base: """
        struct Calculator {
          func total(of values: [Int]) -> Int {
            guard !values.isEmpty else { return 0 }
            if values.count == 1 {
              return values[0]
            }
            for value in values where value < 0 {
              return -1
            }
            return values.reduce(0, +)
          }
        }

        """,
      head: """
        struct Calculator {
          func total(of values: [Int]) -> Int {
            return values.reduce(0, +)
          }
        }

        """
    )
  )

  /// An agent silences a failing call by discarding its error instead of handling it.
  private static let discardedError = RuleExpectation(
    ruleID: "error_handling_collapse",
    pair: SourcePair(
      path: "Sources/Loader.swift",
      base: """
        struct Loader {
          func load() throws -> Data {
            try read()
          }
        }

        """,
      head: """
        struct Loader {
          func load() -> Data? {
            try? read()
          }
        }

        """
    )
  )

  /// The fixture file, with the assertion on line 5 so a reported line can be asserted exactly.
  private static func source(assertion: String) -> String {
    """
    import XCTest

    final class TotalTests: XCTestCase {
      func testTotal() {
        \(assertion)
      }
    }

    """
  }

  // MARK: - Running

  /// Commits the pair and runs every rule over it, with or without the parser.
  private func evaluate(_ pair: SourcePair, parsed: Bool = true) async throws -> RuleEngine.Result {
    try write(pair.base, to: pair.path)
    let base = try await commit("Add \(pair.path)")
    try write(pair.head, to: pair.path)
    let head = try await commit("Rewrite the assertion")

    let runner = RegressionGuardRunner(
      repositoryDirectory: repositoryURL,
      syntacticEvidenceProvider: parsed
        ? await ProjectingProvider(repository: repository, base: base, head: head)
        : nil
    )
    return try await runner.evaluate(base: base, head: head)
  }

  private var repository: GitRepository { GitRepository(workingDirectory: repositoryURL) }

  @discardableResult
  private func git(_ arguments: [String]) async throws -> String {
    try await repository.run(arguments)
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

/// Reads each requested file at both refs and projects it.
///
/// A prototype, deliberately: the shipping provider batches one `git cat-file --batch` for the
/// whole request set, which the parse performance budget measured at 286x cheaper than a read per
/// file. That cost only exists at the file counts a real diff reaches, and reproducing it here
/// would put the thing under test behind machinery this fixture does not exercise. What this does
/// share with the real one is the part the fixture is for: the source is read out of git at a ref,
/// not handed over as a literal, and `SwiftSyntaxProjection` turns it into the tree the rule sees.
private struct ProjectingProvider: SyntacticEvidenceProvider {
  private let sources: [String: (base: String?, head: String?)]

  var grammar: SyntaxGrammar? { CompiledSyntaxGrammar.current }

  init(repository: GitRepository, base: String, head: String) async {
    var sources: [String: (base: String?, head: String?)] = [:]
    let paths = (try? await repository.run(["diff", "--name-only", base, head]))?
      .split(separator: "\n")
      .map(String.init) ?? []
    for path in paths {
      sources[path] = (
        await repository.show(ref: base, path: path),
        await repository.show(ref: head, path: path)
      )
    }
    self.sources = sources
  }

  func syntacticEvidence(for requests: [SyntacticEvidenceRequest]) -> SyntacticEvidence {
    SyntacticEvidence(
      files: requests.map { request in
        SyntacticFileEvidence(
          path: request.path,
          base: availability(request.basePath, source: sources[request.path]?.base, ref: .base),
          head: availability(request.headPath, source: sources[request.path]?.head, ref: .head)
        )
      }
    )
  }

  /// The three outcomes, kept apart: a side the request never expected is an absence, a side that
  /// was expected and could not be read is a gap, and anything else is a tree.
  private func availability(
    _ path: String?,
    source: String?,
    ref: SyntaxRef
  ) -> SyntaxTreeAvailability {
    guard let path else { return .absent(ref == .base ? .fileAdded : .fileDeleted) }
    guard let source else {
      return .unavailable(.sourceReadFailed, detail: "git show \(ref.rawValue):\(path)")
    }
    return .parsed(SwiftSyntaxProjection.tree(source: source, path: path, ref: ref.rawValue))
  }
}
