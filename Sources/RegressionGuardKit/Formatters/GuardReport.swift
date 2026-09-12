import Foundation

/// A stable, machine-readable finding stored in a guard report.
public struct GuardFinding: Codable, Equatable, Sendable {
  public let id: String
  public let ruleID: String
  public let severity: Severity
  public let file: String
  public let line: Int?
  public let message: String
  public let detail: String?
  public let confidence: String
  public let evidenceReferences: [String]
  public let approved: Bool
  public let remediation: String?
  /// What this finding was judged on: the diff, parsed syntax, or the text approximation of a
  /// syntax detection whose tree never arrived.
  ///
  /// Deferred here by the text rule migration contract, which kept the envelope at version 1
  /// until this ticket could bump it. A degraded finding is the weaker claim, and one that cannot
  /// say so reads exactly like the sharper one.
  public let evidence: ViolationEvidence

  public init(
    violation: Violation,
    confidence: String = "unclassified",
    evidenceReferences: [String] = [],
    approved: Bool = false,
    remediation: String? = nil
  ) {
    self.evidence = violation.evidence
    self.id = Self.makeID(for: violation)
    self.ruleID = violation.ruleID
    self.severity = violation.severity
    self.file = violation.file
    self.line = violation.line
    self.message = violation.message
    self.detail = violation.detail
    self.confidence = confidence
    self.evidenceReferences = evidenceReferences
    self.approved = approved
    self.remediation = remediation ?? Self.remediation(for: violation)
  }

  private static func makeID(for violation: Violation) -> String {
    let line = violation.line.map(String.init) ?? "-"
    return "\(violation.ruleID)|\(violation.file)|\(line)|\(violation.message)"
  }

  /// Decodes a finding written by any schema version this tool has produced.
  ///
  /// A report is an artifact a repository stores and hands back later, so reading is as much a
  /// compatibility surface as writing - and the first consumer of a stored report is this
  /// project's own observer. Synthesised decoding would make `evidence` required and reject every
  /// version 1 report on disk, breaking the calibration path that advisory promotion depends on.
  /// A version 1 finding was reached from the diff and claimed nothing more, so that is what its
  /// absence means.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    ruleID = try container.decode(String.self, forKey: .ruleID)
    severity = try container.decode(Severity.self, forKey: .severity)
    file = try container.decode(String.self, forKey: .file)
    line = try container.decodeIfPresent(Int.self, forKey: .line)
    message = try container.decode(String.self, forKey: .message)
    detail = try container.decodeIfPresent(String.self, forKey: .detail)
    confidence = try container.decode(String.self, forKey: .confidence)
    evidenceReferences = try container.decode([String].self, forKey: .evidenceReferences)
    approved = try container.decode(Bool.self, forKey: .approved)
    remediation = try container.decodeIfPresent(String.self, forKey: .remediation)
    evidence = try container.decodeIfPresent(ViolationEvidence.self, forKey: .evidence) ?? .diff
  }

  /// Deterministic, evidence-bounded remediation per rule, keyed by rule ID.
  ///
  /// A table rather than a `switch`: one entry per family, so adding a rule is a line here and
  /// cannot push a control-flow budget over. A rule with no entry gets no hint, which is the
  /// honest answer for one nobody has written guidance for yet.
  private static let remediationByRuleID: [String: String] = [
    "disabled_or_skipped_test": "Restore test execution. Do not disable or skip tests.",
    "weakened_assertion": "Restore meaningful assertions. Do not weaken or delete assertions.",
    "behavior_deletion": "Restore or explicitly replace the removed validation behavior.",
    "error_handling_collapse":
      "Restore explicit error or optional handling for the failure path.",
    "enforcement_weakening":
      "Restore enforcement. Do not lower thresholds, disable rules, or hide findings.",
    "review_escape":
      "Move the change into a reviewed path or explicitly review generated source.",
    "golden_master_drift":
      "Review the snapshot change before adding its configured approval marker.",
    "coverage_regression":
      "Add meaningful tests. Do not lower coverage thresholds to pass the check.",
    "known_issue_suppression":
      "Fix the failing behavior, or justify the known issue with a tracking reference.",
    "implementation_stubbed":
      "Restore the implementation. Do not replace a body with a trap or a constant.",
    "unreachable_assertion":
      "Move the assertion back where it runs. Do not strand it behind an exit.",
  ]

  private static func remediation(for violation: Violation) -> String? {
    remediationByRuleID[violation.ruleID]
  }
}

/// The versioned machine-readable result of one guard run.
public struct GuardReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let toolVersion: String
  public let repository: String
  public let baseRef: String
  public let headRef: String
  public let runID: String
  public let exitStatus: Int
  public let findings: [GuardFinding]
  /// Every hole in the syntactic evidence this run was judged on.
  ///
  /// In the report, not only on stderr. A report is the artifact a repository keeps, audits, and
  /// feeds to the observer; a degraded run whose report looks identical to a clean one is the
  /// implicit pass the evidence bundle exists to forbid, and log output does not survive.
  public let syntacticEvidenceGaps: [SyntaxEvidenceGap]
  /// The swift-syntax grammar the syntax-aware rules were judged with, absent when the run had
  /// no parser.
  ///
  /// Deferred here by the version pin and grammar coverage decision. Without it, a clean report
  /// from an under-selected parser is indistinguishable from a clean report from a current one.
  public let syntaxGrammar: SyntaxGrammar?
  /// The rules that ran, and whether each could have failed the build.
  ///
  /// An upgrade brings rule IDs no existing configuration mentions. Listing what ran is what lets
  /// a reader tell a family that found nothing from one that was never present.
  public let rules: [ReportedRule]
  /// `true` when an approval marker suppressed the whole run.
  ///
  /// An approved run has no findings and no rules, which without this reads exactly like a guard
  /// that never had any. The report says which it was.
  public let approvalSuppressed: Bool

  public init(
    toolVersion: String,
    repository: String,
    baseRef: String,
    headRef: String,
    runID: String,
    exitStatus: Int = 0,
    findings: [Violation],
    syntacticEvidenceGaps: [SyntaxEvidenceGap] = [],
    syntaxGrammar: SyntaxGrammar? = nil,
    rules: [ReportedRule] = [],
    approvalSuppressed: Bool = false
  ) {
    self.approvalSuppressed = approvalSuppressed
    // Version 2. Three fields arrive at once - a finding's evidence, the run's grammar, and the
    // gaps - and every one of them exists so a weaker run cannot read as a stronger one.
    self.schemaVersion = 2
    self.syntacticEvidenceGaps = syntacticEvidenceGaps
    self.syntaxGrammar = syntaxGrammar
    self.rules = rules
    self.toolVersion = toolVersion
    self.repository = repository
    self.baseRef = baseRef
    self.headRef = headRef
    self.runID = runID
    self.exitStatus = exitStatus
    self.findings = findings.map { GuardFinding(violation: $0) }.sorted { lhs, rhs in
      [lhs.ruleID, lhs.file, String(lhs.line ?? 0), lhs.message]
        .lexicographicallyPrecedes(
          [rhs.ruleID, rhs.file, String(rhs.line ?? 0), rhs.message]
        )
    }
  }

  /// Decodes a report written by any schema version this tool has produced.
  ///
  /// Version 1 knew none of the fields this bump added, and a stored version 1 report has to keep
  /// decoding: the observer reads reports off disk to calibrate rules, so rejecting them would
  /// break the path that promotes an advisory family to blocking. Absent additions decode to
  /// their empty values, which is what they meant before they existed.
  ///
  /// `schemaVersion` is read from the document rather than restamped, so a decoded report still
  /// says which version wrote it.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    toolVersion = try container.decode(String.self, forKey: .toolVersion)
    repository = try container.decode(String.self, forKey: .repository)
    baseRef = try container.decode(String.self, forKey: .baseRef)
    headRef = try container.decode(String.self, forKey: .headRef)
    runID = try container.decode(String.self, forKey: .runID)
    exitStatus = try container.decode(Int.self, forKey: .exitStatus)
    findings = try container.decode([GuardFinding].self, forKey: .findings)
    syntacticEvidenceGaps =
      try container.decodeIfPresent(
        [SyntaxEvidenceGap].self,
        forKey: .syntacticEvidenceGaps
      ) ?? []
    syntaxGrammar = try container.decodeIfPresent(SyntaxGrammar.self, forKey: .syntaxGrammar)
    rules = try container.decodeIfPresent([ReportedRule].self, forKey: .rules) ?? []
    approvalSuppressed =
      try container.decodeIfPresent(Bool.self, forKey: .approvalSuppressed) ?? false
  }
}

/// Encodes a guard report with deterministic key and finding order.
public struct JSONReportFormatter {
  public init() {}

  public func data(for report: GuardReport) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(report)
  }

  public func format(_ report: GuardReport) throws -> String {
    let data = try data(for: report)
    guard let string = String(data: data, encoding: .utf8) else { return "" }
    return string
  }
}
