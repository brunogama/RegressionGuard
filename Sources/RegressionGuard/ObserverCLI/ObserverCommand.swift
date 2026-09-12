import ArgumentParser
import Foundation
import RegressionGuardKit
import RegressionGuardObserver

@main
struct RegressionGuardObserverCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "regression-guard-observer",
    abstract: "Creates reviewed-finding observation artifacts from guard reports."
  )

  @Option(name: .long, help: "Path to a versioned regression-guard JSON report.")
  var reportFile: String

  @Option(
    name: .long,
    help: "Optional JSON map of finding IDs to outcomes or outcome/reference assessments."
  )
  var outcomesFile: String?

  @Option(name: .long, help: "Write the observation JSON to this path instead of standard output.")
  var outputFile: String?

  func run() throws {
    let report = try loadReport()
    let outcomes = try loadOutcomes()
    let observation = ReportObserver().observe(report: report, assessments: outcomes)
    let data = try ObservationJSONFormatter().data(for: observation)

    if let outputFile {
      try data.write(to: URL(fileURLWithPath: outputFile))
      return
    }

    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private func loadReport() throws -> GuardReport {
    let data = try Data(contentsOf: URL(fileURLWithPath: reportFile))
    return try JSONDecoder().decode(GuardReport.self, from: data)
  }

  private func loadOutcomes() throws -> [String: ReviewAssessment] {
    guard let outcomesFile else { return [:] }
    let data = try Data(contentsOf: URL(fileURLWithPath: outcomesFile))
    return try JSONDecoder().decode([String: ReviewAssessment].self, from: data)
  }
}
