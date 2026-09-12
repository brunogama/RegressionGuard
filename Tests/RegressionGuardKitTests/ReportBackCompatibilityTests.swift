import Foundation
import Testing

@testable import RegressionGuardKit

/// A report is an artifact a repository stores and feeds back in later. The observer reads
/// reports written by whatever version produced them, so a version 2 binary that cannot decode a
/// version 1 report breaks the calibration path the whole advisory-promotion story depends on.
@Suite("Report back-compatibility tests")
struct ReportBackCompatibilityTests {
  /// Exactly what a version 1 binary wrote: no `evidence`, no `syntacticEvidenceGaps`, no
  /// `rules`, no `syntaxGrammar`.
  private static let version1Report = """
    {
      "schemaVersion" : 1,
      "toolVersion" : "0.1.0",
      "repository" : "RegressionGuard",
      "baseRef" : "main",
      "headRef" : "HEAD",
      "runID" : "HEAD",
      "exitStatus" : 1,
      "findings" : [
        {
          "id" : "weakened_assertion|Tests/E.swift|12|Assertion was removed.",
          "ruleID" : "weakened_assertion",
          "severity" : "error",
          "file" : "Tests/E.swift",
          "line" : 12,
          "message" : "Assertion was removed.",
          "confidence" : "unclassified",
          "evidenceReferences" : [],
          "approved" : false
        }
      ]
    }
    """

  @Test("a version 1 report still decodes, so the observer can read stored artifacts")
  func decodesVersionOneReport() throws {
    let data = try #require(Self.version1Report.data(using: .utf8))
    let report = try JSONDecoder().decode(GuardReport.self, from: data)

    #expect(report.runID == "HEAD")
    #expect(report.findings.count == 1)
    #expect(report.findings.first?.ruleID == "weakened_assertion")
  }

  @Test("a version 1 finding reads as diff evidence, the only claim it ever made")
  func versionOneFindingDefaultsToDiffEvidence() throws {
    let data = try #require(Self.version1Report.data(using: .utf8))
    let report = try JSONDecoder().decode(GuardReport.self, from: data)

    #expect(report.findings.first?.evidence == .diff)
  }

  @Test("a version 1 report has no rules and no gaps, rather than failing to decode")
  func versionOneReportHasEmptyAdditions() throws {
    let data = try #require(Self.version1Report.data(using: .utf8))
    let report = try JSONDecoder().decode(GuardReport.self, from: data)

    #expect(report.rules.isEmpty)
    #expect(report.syntacticEvidenceGaps.isEmpty)
    #expect(report.syntaxGrammar == nil)
    // The stored version is preserved, not silently restamped as 2.
    #expect(report.schemaVersion == 1)
  }

  @Test("a version 2 report round-trips through encode and decode unchanged")
  func versionTwoRoundTrips() throws {
    let original = GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: [
        Violation(
          ruleID: "implementation_stubbed",
          severity: .warning,
          file: "Sources/A.swift",
          message: "Function body was replaced by a stub instead of implemented.",
          evidence: .syntax
        )
      ],
      syntacticEvidenceGaps: [
        SyntaxEvidenceGap(path: "Sources/A.swift", ref: .base, reason: .parserUnavailable)
      ],
      syntaxGrammar: SyntaxGrammar(alignmentSeries: 603),
      rules: [
        ReportedRule(ruleID: "implementation_stubbed", severity: .warning, blocking: false)
      ]
    )

    let data = try JSONReportFormatter().data(for: original)
    let decoded = try JSONDecoder().decode(GuardReport.self, from: data)

    #expect(decoded == original)
    #expect(decoded.schemaVersion == 2)
  }
}
