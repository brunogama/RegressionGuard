import Foundation
import Testing

/// The parser reaching a real run, asserted from outside the process.
///
/// Every layer below this has its own tests, and all of them passed while `CheckCommand` built its
/// runner without a provider - so every shipped run took the parserless path, degraded every
/// tree-reading detection, and found nothing at all for the families that have no text fallback.
/// Only the built binary can say whether that is wired, so this suite runs it.
@Suite("Syntactic evidence end-to-end tests")
struct SyntacticEvidenceEndToEndTests {

  @Test("the shipped binary parses the change and names the grammar it judged with")
  func theBinaryParses() throws {
    let repository = try ScratchRepository()
    defer { repository.remove() }

    try repository.write(Self.implemented, to: "Sources/Calculator.swift")
    let base = try repository.commit("Add the calculator")
    try repository.write(Self.stubbed, to: "Sources/Calculator.swift")
    let head = try repository.commit("Stub the calculator")

    let report = try repository.checkReport(base: base, head: head)

    #expect(report.syntaxGrammar?.alignmentSeries == 603)
    #expect(
      report.syntacticEvidenceGaps.isEmpty,
      "a run that parsed nothing reports every file as a gap: \(report.syntacticEvidenceGaps)"
    )
  }

  /// `implementation_stubbed` has no text fallback at all, so it is the sharpest proof that the
  /// trees arrived: without a parser this finding cannot exist by any route.
  @Test("an AST-only family fires through the CLI")
  func anASTOnlyFamilyFires() throws {
    let repository = try ScratchRepository()
    defer { repository.remove() }

    try repository.write(Self.implemented, to: "Sources/Calculator.swift")
    let base = try repository.commit("Add the calculator")
    try repository.write(Self.stubbed, to: "Sources/Calculator.swift")
    let head = try repository.commit("Stub the calculator")

    let report = try repository.checkReport(base: base, head: head)
    let finding = try #require(
      report.findings.first { $0.ruleID == "implementation_stubbed" },
      "no implementation_stubbed finding in \(report.findings.map(\.ruleID))"
    )

    #expect(finding.evidence == "syntax")
  }

  @Test("a working-tree run parses the checkout, with no head ref at all")
  func aWorkingTreeRunParses() throws {
    let repository = try ScratchRepository()
    defer { repository.remove() }

    try repository.write(Self.implemented, to: "Sources/Calculator.swift")
    let base = try repository.commit("Add the calculator")
    try repository.write(Self.stubbed, to: "Sources/Calculator.swift")

    let report = try repository.checkReport(base: base, head: nil)

    #expect(report.syntacticEvidenceGaps.isEmpty)
    #expect(report.findings.contains { $0.ruleID == "implementation_stubbed" })
  }

  /// The budget for this feature is one subprocess per run rather than a number of milliseconds:
  /// reading source per file is linear in the file count and was measured at 286x the batch on a
  /// 504-file diff, which would make the subprocess the entire cost of parsing. Asserted by
  /// recording what the binary actually invoked, because the contract is about spawns and nothing
  /// inside the process can see them.
  @Test("reads every file's source in one git invocation, whatever the file count")
  func readsEverySourceInOneInvocation() throws {
    let repository = try ScratchRepository()
    defer { repository.remove() }

    for index in 1...8 {
      try repository.write(Self.implemented, to: "Sources/Calculator\(index).swift")
    }
    let base = try repository.commit("Add the calculators")
    for index in 1...8 {
      try repository.write(Self.stubbed, to: "Sources/Calculator\(index).swift")
    }
    let head = try repository.commit("Stub the calculators")

    let invocations = try repository.gitInvocationsDuringCheck(base: base, head: head)

    #expect(
      invocations.filter { $0.contains("cat-file") }.count == 1,
      "source reads: \(invocations.filter { $0.contains("cat-file") })"
    )
  }

  private static let implemented = """
    struct Calculator {
      func total(of values: [Int]) -> Int {
        values.reduce(0, +)
      }
    }

    """

  private static let stubbed = """
    struct Calculator {
      func total(of values: [Int]) -> Int {
        fatalError("not implemented")
      }
    }

    """
}
