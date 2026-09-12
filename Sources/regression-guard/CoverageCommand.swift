import ArgumentParser
import Foundation
import RegressionGuardKit


struct Coverage: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "coverage",
    abstract: "Compare two `llvm-cov export` JSON reports and fail on a coverage drop."
  )

  @Option(name: .long, help: "Path to the base ref's llvm-cov export JSON.")
  var baseReport: String

  @Option(name: .long, help: "Path to the head ref's llvm-cov export JSON.")
  var headReport: String

  @Option(name: .long, help: "Maximum allowed coverage drop, in percentage points.")
  var maxDropPercent: Double = 0.5

  @Option(name: .long, help: "text, json, or github.")
  var format: String = "text"

  func run() throws {
    let baseData = try Data(contentsOf: URL(fileURLWithPath: baseReport))
    let headData = try Data(contentsOf: URL(fileURLWithPath: headReport))
    let violations = try CoverageRegressionRule.checkCoverage(
      baseReportJSON: baseData,
      headReportJSON: headData,
      maxDropPercent: maxDropPercent,
      severity: .error
    )

    Console.write(formatter.format(violations))
    if !violations.isEmpty {
      throw ExitCode.failure
    }
  }

  private var formatter: ViolationFormatter {
    switch format {
    case "json": return JSONFormatter()
    case "github": return GitHubAnnotationFormatter()
    default: return TextFormatter()
    }
  }
}
