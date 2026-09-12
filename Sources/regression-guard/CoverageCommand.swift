import Commander
import Foundation
import RegressionGuardCommandLine
import RegressionGuardKit

struct Coverage: ParsableCommand {
  static let commandDescription = CommandDescription(
    commandName: "coverage",
    abstract: "Compare two `llvm-cov export` JSON reports and fail on a coverage drop."
  )

  @Option(name: .long, help: "Path to the base ref's llvm-cov export JSON.")
  var baseReport: String = ""

  @Option(name: .long, help: "Path to the head ref's llvm-cov export JSON.")
  var headReport: String = ""

  @Option(name: .long, help: "Maximum allowed coverage drop, in percentage points.")
  var maxDropPercent: Double = 0.5

  @Option(name: .long, help: "text, json, or github.")
  var format: String = "text"

  init() {}

  /// - Throws: `ValidationError` when a required report path is missing or the drop is not a
  ///   number. Both report paths have no default, so an absent one is an error rather than an
  ///   empty path that would fail later as a confusing file-not-found.
  init(options: ParsedOptions) throws {
    self.init()
    baseReport = try options.required("baseReport")
    headReport = try options.required("headReport")
    maxDropPercent = try options.double("maxDropPercent", or: maxDropPercent)
    format = options.string("format", or: format)
  }

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
