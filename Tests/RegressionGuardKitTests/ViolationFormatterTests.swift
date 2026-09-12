import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Violation formatter tests")
struct ViolationFormatterTests {
  @Test("text formatter describes empty results")
  func textFormatterDescribesEmptyResults() {
    #expect(TextFormatter().format([]) == "regression-guard: no violations found.")
  }

  @Test("JSON formatter encodes violations")
  func jsonFormatterEncodesViolations() throws {
    let output = JSONFormatter().format([Self.violation(severity: .warning)])
    let data = try #require(output.data(using: .utf8))
    let violations = try JSONDecoder().decode([Violation].self, from: data)

    #expect(violations.count == 1)
    #expect(violations[0].ruleID == "example_rule")
    #expect(violations[0].severity == .warning)
  }

  @Test("GitHub formatter maps severities and escapes newlines")
  func gitHubFormatterMapsSeverities() {
    let violations = [
      Self.violation(severity: .error, line: 7, message: "first\nsecond"),
      Self.violation(severity: .warning, line: nil),
      Self.violation(severity: .info, line: 9),
    ]

    let output = GitHubAnnotationFormatter().format(violations)

    #expect(output.contains("::error file=Tests/ExampleTests.swift,line=7"))
    #expect(output.contains("first%0Asecond"))
    #expect(output.contains("::warning file=Tests/ExampleTests.swift,title=example_rule"))
    #expect(output.contains("::notice file=Tests/ExampleTests.swift,line=9"))
  }

  @Test("report formatter emits a JSON string")
  func reportFormatterEmitsJSONString() throws {
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: "RegressionGuard",
      baseRef: "main",
      headRef: "HEAD",
      runID: "run",
      findings: [Self.violation(severity: .error)]
    )

    let output = try JSONReportFormatter().format(report)

    #expect(output.contains("\"schemaVersion\" : 1"))
    #expect(output.contains("\"example_rule\""))
  }

  private static func violation(
    severity: Severity,
    line: Int? = 4,
    message: String = "Example finding"
  ) -> Violation {
    Violation(
      ruleID: "example_rule",
      severity: severity,
      file: "Tests/ExampleTests.swift",
      line: line,
      message: message
    )
  }
}
