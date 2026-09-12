import Commander
import Foundation
import RegressionGuardCommandLine
import RegressionGuardKit
import RegressionGuardObserver

/// The `regression-guard-observer` executable.
///
/// One command with no subcommands, so it parses against its own signature directly rather than
/// going through `Program`, whose router requires a command-name token this binary never takes.
@main
struct RegressionGuardObserverCommand: ParsableCommand {
  static let commandDescription = CommandDescription(
    commandName: "regression-guard-observer",
    abstract: "Creates reviewed-finding observation artifacts from guard reports."
  )

  @Option(name: .long, help: "Path to a versioned regression-guard JSON report.")
  var reportFile: String = ""

  @Option(
    name: .long,
    help: "Optional JSON map of finding IDs to outcomes or outcome/reference assessments."
  )
  var outcomesFile: String?

  @Option(name: .long, help: "Write the observation JSON to this path instead of standard output.")
  var outputFile: String?

  init() {}

  /// - Throws: `ValidationError` when `--report-file` is absent; it has no useful default and an
  ///   empty path would surface later as a confusing file-not-found.
  init(options: ParsedOptions) throws {
    self.init()
    reportFile = try options.required("reportFile")
    outcomesFile = options.string("outcomesFile")
    outputFile = options.string("outputFile")
  }

  @MainActor
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    await CommandLineDriver.run {
      let descriptor = CommandDescriptor(
        name: commandDescription.commandName ?? "regression-guard-observer",
        abstract: commandDescription.abstract,
        discussion: commandDescription.discussion,
        signature: CommandSignature.describe(Self())
      )
      guard !CommandLineDriver.wantsHelp(arguments) else {
        CommandLineDriver.write(HelpText.render(descriptor, invokedAs: [descriptor.name]))
        return
      }
      let parsed = try CommandParser(signature: descriptor.signature).parse(arguments: arguments)
      try Self(options: ParsedOptions(parsed)).run()
    }
  }

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
