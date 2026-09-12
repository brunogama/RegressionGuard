import ArgumentParser
import Foundation
import RegressionGuardKit

@main
struct RegressionGuardCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "regression-guard",
    abstract: "Catches shortcuts around failing tests instead of fixing them.",
    subcommands: [Check.self, Coverage.self, Init.self],
    defaultSubcommand: Check.self
  )
}

struct Check: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: "Diff two refs or compare a ref against the working tree."
  )

  @Option(name: .long, help: "Ref to compare against, such as origin/main or a SHA.")
  var base: String = "HEAD"

  @Option(name: .long, help: "Ref to check. Omit to check the working tree against --base.")
  var head: String?

  @Option(name: .long, help: "Repository directory. Defaults to the current directory.")
  var path: String = FileManager.default.currentDirectoryPath

  @Option(name: .long, help: "text, json, or github.")
  var format: String = "text"


  @Option(name: .long, help: "Write the versioned JSON report to this path.")
  var reportFile: String?
  @Option(name: .long, help: "Fail at or above this severity: info, warning, error.")
  var failOn: String = "error"

  func run() throws {
    guard let threshold = Severity(rawValue: failOn) else {
      throw ValidationError("--fail-on must be one of: info, warning, error")
    }

    let runner = RegressionGuardRunner(repositoryDirectory: URL(fileURLWithPath: path))
    let violations = try runner.check(base: base, head: head)
    let hasBlockingFinding = violations.contains { $0.severity >= threshold }
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: URL(fileURLWithPath: path).lastPathComponent,
      baseRef: base,
      headRef: head ?? "working-tree",
      runID: head ?? "working-tree",
      exitStatus: hasBlockingFinding ? 1 : 0,
      findings: violations
    )

    if let reportFile {
      let data = try JSONReportFormatter().data(for: report)
      try data.write(to: URL(fileURLWithPath: reportFile))
    }

    if format == "json" {
      Console.write(try JSONReportFormatter().format(report))
    } else {
      Console.write(formatter.format(violations))
    }

    if hasBlockingFinding {
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

struct Init: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Write a default .regressionguard.yml into the chosen directory."
  )

  @Option(name: .long, help: "Directory to write the config into.")
  var path: String = FileManager.default.currentDirectoryPath

  func run() throws {
    let url = URL(fileURLWithPath: path).appendingPathComponent(".regressionguard.yml")
    if FileManager.default.fileExists(atPath: url.path) {
      Console.write("\(url.path) already exists - leaving it untouched.")
      return
    }
    try Self.defaultConfigYAML.write(to: url, atomically: true, encoding: .utf8)
    Console.write("Wrote \(url.path)")
  }

  static let defaultConfigYAML = """
    # regression-guard configuration.
    # See this repository for the full guide.
    version: 1
    approvalMarker: "regression-guard:approve"

    rules:
      disabled_or_skipped_test:
        enabled: true
        severity: error
      weakened_assertion:
        enabled: true
        severity: error
      production_code_deletion:
        enabled: true
        severity: warning
      golden_master_drift:
        enabled: true
        severity: warning
      review_escape:
        enabled: true
        severity: error
      enforcement_weakening:
        enabled: true
        severity: error
      coverage_regression:
        enabled: true
        severity: error

    ignore:
      - "**/.build/**"
      - "**/Generated/**"
      - "**/*.generated.swift"

    testPaths:
      - "Tests/**"
      - "**/*Tests.swift"
      - "**/*Test.swift"
      - "**/*Spec.swift"

    """
}

private enum Console {
  static func write(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }
}
