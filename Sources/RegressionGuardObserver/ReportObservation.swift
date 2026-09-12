/// A versioned observer artifact derived from one guard report.
public struct ReportObservation: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let runID: String
  public let repository: String?
  public let findings: [ObservedFinding]
  public let calibrations: [RuleCalibration]

  public init(
    runID: String,
    repository: String? = nil,
    findings: [ObservedFinding],
    calibrations: [RuleCalibration] = []
  ) {
    self.schemaVersion = 1
    self.runID = runID
    self.repository = repository
    self.findings = findings
    self.calibrations = calibrations
  }
}
