import XCTest
@testable import RegressionGuardKit

final class CoverageRegressionRuleTests: XCTestCase {

  private func report(percent: Double) -> Data {
    let json = """
      {"data":[{"totals":{"lines":{"percent":\(percent)}}}]}
      """
    return json.data(using: .utf8)!
  }

  func testFlagsADropBeyondThreshold() throws {
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: report(percent: 90.0),
      headReportJSON: report(percent: 85.0),
      maxDropPercent: 0.5,
      severity: .error
    )
    XCTAssertEqual(violations.count, 1)
    XCTAssertEqual(violations.first?.severity, .error)
  }

  func testAllowsADropWithinThreshold() throws {
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: report(percent: 90.0),
      headReportJSON: report(percent: 89.8),
      maxDropPercent: 0.5,
      severity: .error
    )
    XCTAssertTrue(violations.isEmpty)
  }

  func testAllowsCoverageIncrease() throws {
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: report(percent: 90.0),
      headReportJSON: report(percent: 95.0),
      maxDropPercent: 0.5,
      severity: .error
    )
    XCTAssertTrue(violations.isEmpty)
  }
}
