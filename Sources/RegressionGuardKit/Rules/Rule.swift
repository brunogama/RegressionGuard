import Foundation


/// An observable signal that can be present or explicitly unavailable in an evidence bundle.
public enum EvidenceSignal: String, Codable, CaseIterable, Hashable, Sendable {
  case coverage
  case ciConfiguration
  case generatedPaths
}

/// The old and new content available for a changed path.
public struct FileContentEvidence: Codable, Equatable, Sendable {
  public let old: String?
  public let new: String?

  public init(old: String?, new: String?) {
    self.old = old
    self.new = new
  }
}

/// Classification signals collected for one changed path.
public struct PathEvidence: Codable, Equatable, Sendable {
  public let isTest: Bool
  public let isIgnored: Bool
  public let isGenerated: Bool

  public init(isTest: Bool, isIgnored: Bool, isGenerated: Bool) {
    self.isTest = isTest
    self.isIgnored = isIgnored
    self.isGenerated = isGenerated
  }
}

/// Commit and optional pull-request context for a guard run.
public struct CommitEvidence: Codable, Equatable, Sendable {
  public let baseRef: String
  public let headRef: String
  public let messages: [String]
  public let pullRequest: PullRequestEvidence?

  public init(
    baseRef: String,
    headRef: String,
    messages: [String],
    pullRequest: PullRequestEvidence? = nil
  ) {
    self.baseRef = baseRef
    self.headRef = headRef
    self.messages = messages
    self.pullRequest = pullRequest
  }
}

/// Minimal pull-request metadata that can be correlated by the observer.
public struct PullRequestEvidence: Codable, Equatable, Sendable {
  public let number: Int
  public let title: String
  public let body: String?

  public init(number: Int, title: String, body: String? = nil) {
    self.number = number
    self.title = title
    self.body = body
  }
}

/// Repository-wide line-coverage measurement, when collection succeeded.
public struct CoverageEvidence: Codable, Equatable, Sendable {
  public let lineCoverage: Double
  public let baseLineCoverage: Double?

  public init(lineCoverage: Double, baseLineCoverage: Double? = nil) {
    self.lineCoverage = lineCoverage
    self.baseLineCoverage = baseLineCoverage
  }
}

/// Repository-wide CI configuration evidence, when collection succeeded.
public struct CIConfigurationEvidence: Codable, Equatable, Sendable {
  public let changedPaths: [String]

  public init(changedPaths: [String]) {
    self.changedPaths = changedPaths
  }
}

/// Optional repository-wide signals and explicit collection gaps.
public struct RepositoryEvidence: Codable, Equatable, Sendable {
  public let coverage: CoverageEvidence?
  public let ciConfiguration: CIConfigurationEvidence?
  public let generatedPaths: [String]?
  public let unavailableSignals: Set<EvidenceSignal>

  public init(
    coverage: CoverageEvidence? = nil,
    ciConfiguration: CIConfigurationEvidence? = nil,
    generatedPaths: [String]? = nil,
    unavailableSignals: Set<EvidenceSignal> = []
  ) {
    self.coverage = coverage
    self.ciConfiguration = ciConfiguration
    self.generatedPaths = generatedPaths
    self.unavailableSignals = unavailableSignals
  }
}

/// The single canonical input shared by every rule evaluation.
public struct EvidenceBundle: Codable, Equatable, Sendable {
  public let fileDiffs: [FileDiff]
  public let fileContents: [String: FileContentEvidence]
  public let pathEvidence: [String: PathEvidence]
  public let commit: CommitEvidence
  public let repository: RepositoryEvidence
  /// Parsed base and head trees, for the files some enabled rule asked to have parsed. A third
  /// kind of evidence alongside the diff-local and repository-wide signals above.
  public let syntax: SyntacticEvidence

  public init(
    fileDiffs: [FileDiff],
    fileContents: [String: FileContentEvidence] = [:],
    pathEvidence: [String: PathEvidence] = [:],
    commit: CommitEvidence,
    repository: RepositoryEvidence = RepositoryEvidence(),
    syntax: SyntacticEvidence = .none
  ) {
    self.fileDiffs = fileDiffs
    self.fileContents = fileContents
    self.pathEvidence = pathEvidence
    self.commit = commit
    self.repository = repository
    self.syntax = syntax
  }

  public func withSyntacticEvidence(_ syntax: SyntacticEvidence) -> Self {
    Self(
      fileDiffs: fileDiffs,
      fileContents: fileContents,
      pathEvidence: pathEvidence,
      commit: commit,
      repository: repository,
      syntax: syntax
    )
  }
}
/// A single, independently-testable detector. Each rule looks at one `FileDiff` at a time and
/// returns zero or more `Violation`s. Keeping rules per-file (rather than handed the whole diff)
/// makes them trivial to unit test with a hand-written diff fixture.
public protocol Rule {
  static var ruleID: String { get }
  static var defaultSeverity: Severity { get }
  static var inspectsIgnoredPaths: Bool { get }
  /// `true` when this rule reads parsed syntax. A rule never parses for itself: it declares the
  /// need here, and the engine resolves every declared file in one batched call before evaluating.
  static var requiresSyntacticEvidence: Bool { get }
  func evaluate(evidence: EvidenceBundle, context: RuleContext) -> [Violation]
  /// - Returns: violations found in `fileDiff`. Do not filter by config `enabled` here -
  ///   the engine does that before calling `evaluate`.
  func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation]
  /// - Returns: the files this rule wants parsed out of `fileDiff`. Override to narrow further
  ///   than "every Swift file I can see".
  func syntacticEvidenceRequests(for fileDiff: FileDiff) -> [SyntacticEvidenceRequest]
}

public extension Rule {
  func evaluate(evidence: EvidenceBundle, context: RuleContext) -> [Violation] {
    evidence.fileDiffs.flatMap { evaluate(fileDiff: $0, context: context) }
  }

  func syntacticEvidenceRequests(for fileDiff: FileDiff) -> [SyntacticEvidenceRequest] {
    guard Self.requiresSyntacticEvidence, fileDiff.isSwiftSource else { return [] }
    return [SyntacticEvidenceRequest(fileDiff: fileDiff)]
  }

  static var inspectsIgnoredPaths: Bool { false }
  static var requiresSyntacticEvidence: Bool { false }
  static func settings(from context: RuleContext) -> RuleSettings {
    context.configuration.settings(
      for: ruleID,
      default: RuleSettings(enabled: true, severity: defaultSeverity)
    )
  }
}

/// Flags meaningful changes that have been moved into ignored or generated paths.
public struct ReviewEscapeRule: Rule {
  public static let ruleID = "review_escape"
  public static let defaultSeverity = Severity.error
  public static let inspectsIgnoredPaths = true

  public init() {}

  public func evaluate(fileDiff: FileDiff, context: RuleContext) -> [Violation] {
    guard context.pathClassifier.isIgnored(fileDiff.displayPath) else { return [] }
    guard let line = Self.firstMeaningfulLine(in: fileDiff) else { return [] }
    return [
      Violation(
        ruleID: Self.ruleID,
        severity: Self.settings(from: context).severity,
        file: fileDiff.displayPath,
        line: line.number,
        message: "Meaningful change moved into an ignored or generated path.",
        detail: line.text.trimmingCharacters(in: .whitespaces)
      )
    ]
  }

  private static func firstMeaningfulLine(in fileDiff: FileDiff) -> DiffLine? {
    (fileDiff.removedLines + fileDiff.addedLines).first { line in
      !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}
