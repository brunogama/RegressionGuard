import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Coverage regression rule tests")
struct CoverageRegressionRuleTests {

  private func report(percent: Double) -> Data {
    let json = """
      {"data":[{"totals":{"lines":{"percent":\(percent)}}}]}
      """
    return json.data(using: .utf8)!
  }

  @Test("flags a drop beyond the threshold")
  func flagsADropBeyondThreshold() throws {
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: report(percent: 90.0),
      headReportJSON: report(percent: 85.0),
      maxDropPercent: 0.5,
      severity: .error
    )
    #expect(violations.count == 1)
    #expect(violations.first?.severity == .error)
  }

  @Test("allows a drop within the threshold")
  func allowsADropWithinThreshold() throws {
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: report(percent: 90.0),
      headReportJSON: report(percent: 89.8),
      maxDropPercent: 0.5,
      severity: .error
    )
    #expect(violations.isEmpty)
  }

  @Test("allows a coverage increase")
  func allowsCoverageIncrease() throws {
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: report(percent: 90.0),
      headReportJSON: report(percent: 95.0),
      maxDropPercent: 0.5,
      severity: .error
    )
    #expect(violations.isEmpty)
  }
}
