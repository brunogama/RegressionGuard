import Foundation

/// Coverage comparison is a whole-repository metric, not a per-file diff check.
public struct CoverageRegressionRule: Rule {
  public static let ruleID = "coverage_regression"
  public static let defaultSeverity = Severity.error

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    []
  }

  /// Compares two `llvm-cov export -format=text` JSON reports' overall line coverage.
  public static func checkCoverage(
    baseReportJSON: Data,
    headReportJSON: Data,
    maxDropPercent: Double,
    severity: Severity
  ) throws -> [Violation] {
    let basePercent = try Self.totalLinePercent(from: baseReportJSON)
    let headPercent = try Self.totalLinePercent(from: headReportJSON)
    let drop = basePercent - headPercent

    guard drop > maxDropPercent else { return [] }

    return [
      Violation(
        ruleID: ruleID,
        severity: severity,
        file: "<repository>",
        message: coverageDropMessage(
          drop: drop,
          basePercent: basePercent,
          headPercent: headPercent,
          maxDropPercent: maxDropPercent
        ),
        detail: nil
      )
    ]
  }

  private static func coverageDropMessage(
    drop: Double,
    basePercent: Double,
    headPercent: Double,
    maxDropPercent: Double
  ) -> String {
    String(
      format: "Line coverage dropped by %.2f%% (%.2f%% -> %.2f%%), threshold %.2f%%.",
      drop,
      basePercent,
      headPercent,
      maxDropPercent
    )
  }

  private static func totalLinePercent(from json: Data) throws -> Double {
    let decoded = try JSONDecoder().decode(CoverageExport.self, from: json)
    guard let first = decoded.data.first else {
      throw CoverageReportError.empty
    }
    return first.totals.lines.percent
  }
}

private struct CoverageExport: Decodable {
  let data: [CoverageDataEntry]
}

private struct CoverageDataEntry: Decodable {
  let totals: CoverageTotals
}

private struct CoverageTotals: Decodable {
  let lines: CoverageLines
}

private struct CoverageLines: Decodable {
  let percent: Double
}

enum CoverageReportError: Error, CustomStringConvertible {
  case empty
  var description: String { "Coverage report contained no data entries." }
}
