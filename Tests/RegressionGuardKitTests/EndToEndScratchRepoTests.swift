import XCTest
@testable import RegressionGuardKit

/// Exercises the full pipeline (real `git`, real diffs, real `RuleEngine`) against a throwaway
/// repository, simulating exactly the scenario this project exists for: an agent gets a test
/// failing, and instead of fixing the bug, disables the test.
final class EndToEndScratchRepoTests: XCTestCase {

  private var repoURL: URL!

  override func setUpWithError() throws {
    repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try sh(["init", "-q", "-b", "main"])
    try sh(["config", "user.email", "test@example.com"])
    try sh(["config", "user.name", "Regression Guard Tests"])
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: repoURL)
  }

  @discardableResult
  private func sh(_ args: [String]) throws -> String {
    try GitRepository(workingDirectory: repoURL).run(args)
  }

  private func write(_ contents: String, to relativePath: String) throws {
    let url = repoURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  func testCatchesAnAgentDisablingATestInsteadOfFixingIt() throws {
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
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Add commutativity test"])
    let base = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

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
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Fix flaky test"])
    let head = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

    let violations = try RegressionGuardRunner(repositoryDirectory: repoURL).check(
      base: base,
      head: head
    )

    XCTAssertTrue(
      violations.contains { $0.ruleID == DisabledOrSkippedTestRule.ruleID },
      "expected a disabled_or_skipped_test violation, got: \(violations)"
    )
  }

  func testCatchesARenamedTestFunction() throws {
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
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Add commutativity test"])
    let base = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

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
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Rename test function"])
    let head = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

    let violations = try RegressionGuardRunner(repositoryDirectory: repoURL).check(
      base: base,
      head: head
    )

    XCTAssertTrue(
      violations.contains { $0.ruleID == DisabledOrSkippedTestRule.ruleID },
      "expected a disabled_or_skipped_test violation, got: \(violations)"
    )
  }

  func testDoesNotFlagALegitimateFix() throws {

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
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Add (buggy) add function"])
    let base = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

    // The real fix: correct the implementation, leave the test untouched.
    try write("func add(_ a: Int, _ b: Int) -> Int { a + b }", to: "Sources/Math.swift")
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Fix add() to actually add"])
    let head = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

    let violations = try RegressionGuardRunner(repositoryDirectory: repoURL).check(
      base: base,
      head: head
    )
    XCTAssertTrue(
      violations.isEmpty,
      "expected no violations for a legitimate fix, got: \(violations)"
    )
  }

  func testHonorsApprovalMarkerForCharacterizationDrift() throws {
    try write("original output", to: "Sources/__GoldenMasters__/testRender.snapshot.txt")
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Record baseline"])
    let base = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

    try write(
      "intentionally updated output",
      to: "Sources/__GoldenMasters__/testRender.snapshot.txt"
    )
    try sh(["add", "."])
    try sh(["commit", "-q", "-m", "Update rendering\n\nregression-guard:approve"])
    let head = try sh(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

    let violations = try RegressionGuardRunner(repositoryDirectory: repoURL).check(
      base: base,
      head: head
    )
    XCTAssertTrue(
      violations.isEmpty,
      "approved baseline update should not be flagged, got: \(violations)"
    )
  }
}
