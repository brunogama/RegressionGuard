import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Guard report tests")
struct GuardReportTests {
  @Test("encodes a versioned report envelope")
  func encodesVersionedReportEnvelope() throws {
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: [
        Violation(
          ruleID: "weakened_assertion",
          severity: .error,
          file: "Tests/Example.swift",
          line: 12,
          message: "Assertion was removed."
        )
      ]
    )

    let data = try JSONReportFormatter().data(for: report)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(object["schemaVersion"] as? Int == 1)
    #expect(object["toolVersion"] as? String == "0.1.0")
    #expect(object["runID"] as? String == "HEAD")
    #expect((object["findings"] as? [[String: Any]])?.count == 1)
  }

  @Test("adds evidence-bounded remediation only for known rules")
  func addsSafeRemediationHints() {
    let knownRules = [
      "disabled_or_skipped_test",
      "weakened_assertion",
      "behavior_deletion",
      "error_handling_collapse",
      "enforcement_weakening",
      "review_escape",
      "golden_master_drift",
      "coverage_regression",
    ]
    let remediations = knownRules.compactMap { report(for: $0).findings.first?.remediation }
    let disabledTestHint = report(for: "disabled_or_skipped_test").findings.first?.remediation

    #expect(remediations.count == knownRules.count)
    #expect(disabledTestHint?.contains("Restore") == true)
    #expect(disabledTestHint?.contains("Do not disable") == true)
    #expect(report(for: "unknown_rule").findings.first?.remediation == nil)
  }

  private func report(for ruleID: String) -> GuardReport {
    GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: [
        Violation(
          ruleID: ruleID,
          severity: .error,
          file: "Tests/Example.swift",
          message: "Test execution was disabled."
        )
      ]
    )
  }

  @Test("sorts findings by stable rule and location keys")
  func sortsFindingsDeterministically() {
    let later = Violation(
      ruleID: "z_rule",
      severity: .warning,
      file: "Sources/Z.swift",
      line: 20,
      message: "Later"
    )
    let earlier = Violation(
      ruleID: "a_rule",
      severity: .error,
      file: "Sources/A.swift",
      line: 4,
      message: "Earlier"
    )
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "HEAD",
      findings: [later, earlier]
    )

    #expect(report.findings.map(\.ruleID) == ["a_rule", "z_rule"])
  }
}
