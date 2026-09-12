import Foundation
import Testing
@testable import RegressionGuardKit

/// Exercises the full pipeline (real `git`, real diffs, real `RuleEngine`) against a throwaway
/// repository, simulating exactly the scenario this project exists for: an agent gets a test
/// failing, and instead of fixing the bug, disables the test.
///
/// A class rather than a struct so `deinit` can remove the repository; Swift Testing builds one
/// instance per test, so every case gets a repository of its own.
@Suite("End-to-end scratch repository tests")
final class EndToEndScratchRepoTests {

  private let repoURL: URL

  init() async throws {
    repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try await sh(["init", "-q", "-b", "main"])
    try await sh(["config", "user.email", "test@example.com"])
    try await sh(["config", "user.name", "Regression Guard Tests"])
  }

  deinit {
    try? FileManager.default.removeItem(at: repoURL)
  }

  @discardableResult
  private func sh(_ args: [String]) async throws -> String {
    try await GitRepository(workingDirectory: repoURL).run(args)
  }

  private func write(_ contents: String, to relativePath: String) throws {
    let url = repoURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  /// Stages everything, commits it with `message`, and returns the resulting SHA.
  private func commit(_ message: String) async throws -> String {
    try await sh(["add", "."])
    try await sh(["commit", "-q", "-m", message])
    return try await sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func check(base: String, head: String) async throws -> [Violation] {
    try await RegressionGuardRunner(repositoryDirectory: repoURL).check(base: base, head: head)
  }

  @Test("catches an agent disabling a test instead of fixing it")
  func catchesADisabledTest() async throws {
    try write(
      """
      import XCTest
      final class MathTests: XCTestCase {
          func testAdditionIsCommutative() {
              XCTAssertEqual(add(2, 3), add(3, 2))
          }
      }
      """,
      to: "Tests/MathTests.swift"
    )
    let base = try await commit("Add commutativity test")

    // The "agent" gets stuck fixing `add` and disables the test instead.
    try write(
      """
      import XCTest
      final class MathTests: XCTestCase {
          func testAdditionIsCommutative() throws {
              throw XCTSkip("flaky on CI")
          }
      }
      """,
      to: "Tests/MathTests.swift"
    )
    let head = try await commit("Fix flaky test")

    let violations = try await check(base: base, head: head)

    #expect(
      violations.contains { $0.ruleID == DisabledOrSkippedTestRule.ruleID },
      "expected a disabled_or_skipped_test violation, got: \(violations)"
    )
  }

  @Test("catches a renamed test function")
  func catchesARenamedTestFunction() async throws {
    try write(
      """
      import XCTest
      final class MathTests: XCTestCase {
          func testAdditionIsCommutative() {
              XCTAssertEqual(add(2, 3), add(3, 2))
          }
      }
      """,
      to: "Tests/MathTests.swift"
    )
    let base = try await commit("Add commutativity test")

    try write(
      """
      import XCTest
      final class MathTests: XCTestCase {
          func additionIsCommutative() {
              XCTAssertEqual(add(2, 3), add(3, 2))
          }
      }
      """,
      to: "Tests/MathTests.swift"
    )
    let head = try await commit("Rename test function")

    let violations = try await check(base: base, head: head)

    #expect(
      violations.contains { $0.ruleID == DisabledOrSkippedTestRule.ruleID },
      "expected a disabled_or_skipped_test violation, got: \(violations)"
    )
  }

  @Test("does not flag a legitimate fix")
  func doesNotFlagALegitimateFix() async throws {
    try write(
      """
      import XCTest
      final class MathTests: XCTestCase {
          func testAdditionIsCommutative() {
              XCTAssertEqual(add(2, 3), add(3, 2))
          }
      }
      """,
      to: "Tests/MathTests.swift"
    )
    try write("func add(_ a: Int, _ b: Int) -> Int { a - b }", to: "Sources/Math.swift")
    let base = try await commit("Add (buggy) add function")

    // The real fix: correct the implementation, leave the test untouched.
    try write("func add(_ a: Int, _ b: Int) -> Int { a + b }", to: "Sources/Math.swift")
    let head = try await commit("Fix add() to actually add")

    let violations = try await check(base: base, head: head)

    #expect(violations.isEmpty, "expected no violations for a legitimate fix, got: \(violations)")
  }

  /// Overloads are ordinary Swift: two functions in one file can share a name. Keying the head
  /// file's functions by name alone used to trap, so the guard crashed on any test file holding
  /// an overload set instead of reporting on it.
  @Test("survives overloaded function names in a test file")
  func survivesOverloadedFunctionNames() async throws {
    try write(
      """
      import XCTest
      final class RuleTests: XCTestCase {
          func evaluate(one: Int) -> Int { one }
          func evaluate(two: String) -> String { two }
          func testUsesBothOverloads() {
              XCTAssertEqual(evaluate(one: 1), 1)
              XCTAssertEqual(evaluate(two: "a"), "a")
          }
      }
      """,
      to: "Tests/RuleTests.swift"
    )
    let base = try await commit("Add overloaded helpers")

    try write(
      """
      import XCTest
      final class RuleTests: XCTestCase {
          func evaluate(one: Int) -> Int { one }
          func evaluate(two: String) -> String { two }
          func testUsesBothOverloads() {
              XCTAssertEqual(evaluate(one: 1), 1)
              XCTAssertEqual(evaluate(two: "b"), "b")
          }
      }
      """,
      to: "Tests/RuleTests.swift"
    )
    let head = try await commit("Adjust the second overload's expectation")

    let violations = try await check(base: base, head: head)

    #expect(
      !violations.contains { $0.ruleID == DisabledOrSkippedTestRule.ruleID },
      "an untouched test function should not be reported, got: \(violations)"
    )
  }

  /// A test that shares its name with a plain helper still has to be caught when it loses its
  /// `@Test` attribute: the overload set no longer runs as a test at all.
  @Test("catches lost test identity in an overload set")
  func catchesLostTestIdentityInAnOverloadSet() async throws {
    try write(
      """
      import Testing
      struct RuleTests {
          func check(one: Int) -> Int { one }
          @Test
          func check() { #expect(add(2, 3) == 5) }
      }
      """,
      to: "Tests/RuleTests.swift"
    )
    let base = try await commit("Add a test beside a same-named helper")

    try write(
      """
      import Testing
      struct RuleTests {
          func check(one: Int) -> Int { one }
          func check() { #expect(add(2, 3) == 5) }
      }
      """,
      to: "Tests/RuleTests.swift"
    )
    let head = try await commit("Drop the test attribute")

    let violations = try await check(base: base, head: head)

    #expect(
      violations.contains { $0.ruleID == DisabledOrSkippedTestRule.ruleID },
      "expected a disabled_or_skipped_test violation, got: \(violations)"
    )
  }

  @Test("honors the approval marker for characterization drift")
  func honorsApprovalMarkerForCharacterizationDrift() async throws {
    try write("original output", to: "Sources/__GoldenMasters__/testRender.snapshot.txt")
    let base = try await commit("Record baseline")

    try write(
      "intentionally updated output",
      to: "Sources/__GoldenMasters__/testRender.snapshot.txt"
    )
    let head = try await commit("Update rendering\n\nregression-guard:approve")

    let violations = try await check(base: base, head: head)

    #expect(
      violations.isEmpty,
      "approved baseline update should not be flagged, got: \(violations)"
    )
  }
}
