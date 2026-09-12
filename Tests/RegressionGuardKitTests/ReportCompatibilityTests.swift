import Foundation
import Testing

@testable import RegressionGuardKit

/// What a guarded repository sees when it upgrades to a syntax-aware guard: a bumped envelope,
/// findings that say what judged them, and a run that cannot look clean when it was degraded.
@Suite("Report compatibility tests")
struct ReportCompatibilityTests {
  private func report(
    findings: [Violation] = [],
    gaps: [SyntaxEvidenceGap] = [],
    grammar: SyntaxGrammar? = nil,
    rules: [ReportedRule] = []
  ) -> GuardReport {
    GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: findings,
      syntacticEvidenceGaps: gaps,
      syntaxGrammar: grammar,
      rules: rules
    )
  }

  private func object(_ report: GuardReport) throws -> [String: Any] {
    let data = try JSONReportFormatter().data(for: report)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test("the envelope carries version 2, because its shape changed")
  func envelopeIsVersionTwo() throws {
    #expect(try object(report())["schemaVersion"] as? Int == 2)
  }

  @Test("a finding records what judged it, so a degraded one cannot pass as the sharper claim")
  func findingRecordsItsEvidence() throws {
    let degraded = Violation(
      ruleID: "weakened_assertion",
      severity: .error,
      file: "Tests/Example.swift",
      message: "Assertion was removed.",
      evidence: .degradedDiff
    )
    let findings = try #require(try object(report(findings: [degraded]))["findings"] as? [[String: Any]])

    #expect(findings.first?["evidence"] as? String == "degradedDiff")
  }

  @Test("evidence defaults to the diff for a finding that never asked for a tree")
  func findingDefaultsToDiffEvidence() throws {
    let plain = Violation(
      ruleID: "review_escape",
      severity: .error,
      file: "Sources/Generated.swift",
      message: "Change escaped review."
    )
    let findings = try #require(try object(report(findings: [plain]))["findings"] as? [[String: Any]])

    #expect(findings.first?["evidence"] as? String == "diff")
  }

  @Test("the report carries the evidence gaps, so a degraded run is auditable after the fact")
  func reportCarriesEvidenceGaps() throws {
    let gap = SyntaxEvidenceGap(
      path: "Sources/A.swift",
      ref: .base,
      reason: .parserUnavailable,
      detail: "No Swift parser was supplied to this run."
    )
    let gaps = try #require(
      try object(report(gaps: [gap]))["syntacticEvidenceGaps"] as? [[String: Any]]
    )

    #expect(gaps.count == 1)
    #expect(gaps.first?["path"] as? String == "Sources/A.swift")
    #expect(gaps.first?["reason"] as? String == "parserUnavailable")
  }

  @Test("the report names the rules that ran, so a silent family is not mistaken for a clean one")
  func reportNamesTheRulesThatRan() throws {
    let rules = [
      ReportedRule(ruleID: "implementation_stubbed", severity: .warning, blocking: false),
      ReportedRule(ruleID: "weakened_assertion", severity: .error, blocking: true),
    ]
    let encoded = try #require(try object(report(rules: rules))["rules"] as? [[String: Any]])

    #expect(encoded.count == 2)
    #expect(encoded.first?["ruleID"] as? String == "implementation_stubbed")
    #expect(encoded.first?["blocking"] as? Bool == false)
    #expect(encoded.last?["blocking"] as? Bool == true)
  }

  @Test("a run with no parser records no grammar rather than implying one")
  func omitsGrammarWithoutParser() throws {
    #expect(try object(report())["syntaxGrammar"] == nil)
  }

  @Test("a syntax-aware run records the grammar that judged it")
  func recordsGrammar() throws {
    let encoded = try object(report(grammar: SyntaxGrammar(alignmentSeries: 603)))
    let grammar = try #require(encoded["syntaxGrammar"] as? [String: Any])

    #expect(grammar["alignmentSeries"] as? Int == 603)
  }

  @Test("a rule is advisory exactly when it cannot reach the blocking threshold")
  func blockingReflectsTheThreshold() {
    #expect(!ReportedRule(ruleID: "a", severity: .warning, failOn: .error).blocking)
    #expect(ReportedRule(ruleID: "b", severity: .error, failOn: .error).blocking)
    #expect(ReportedRule(ruleID: "c", severity: .warning, failOn: .warning).blocking)
  }
}
