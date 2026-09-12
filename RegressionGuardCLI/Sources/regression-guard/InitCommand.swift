import Commander
import Foundation
import RegressionGuardCommandLine

struct Init: ParsableCommand {
  static let commandDescription = CommandDescription(
    commandName: "init",
    abstract: "Write a default .regressionguard.yml into the chosen directory."
  )

  @Option(name: .long, help: "Directory to write the config into.")
  var path: String = FileManager.default.currentDirectoryPath

  init() {}

  init(options: ParsedOptions) {
    self.init()
    path = options.string("path", or: path)
  }

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

      # Advisory families that need parsed syntax. They report at `warning`, which the default
      # `--fail-on error` does not block on, so they are visible without turning a build red.
      # Raise a severity to `error` to adopt one, or set `enabled: false` to defer it.
      known_issue_suppression:
        enabled: true
        severity: warning
      implementation_stubbed:
        enabled: true
        severity: warning
      unreachable_assertion:
        enabled: true
        severity: warning

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
