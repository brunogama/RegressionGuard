import Foundation

public enum Severity: String, Codable, Comparable, CaseIterable, Sendable {
  case info
  case warning
  case error

  private var rank: Int {
    switch self {
    case .info: return 0
    case .warning: return 1
    case .error: return 2
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// A single finding raised by a `Rule` while inspecting a diff.
public struct Violation: Codable, Equatable, Sendable {
  public let ruleID: String
  public var severity: Severity
  public let file: String
  public var line: Int?
  public let message: String
  public var detail: String?

  public init(
    ruleID: String,
    severity: Severity,
    file: String,
    line: Int? = nil,
    message: String,
    detail: String? = nil
  ) {
    self.ruleID = ruleID
    self.severity = severity
    self.file = file
    self.line = line
    self.message = message
    self.detail = detail
  }
}


/// Per-rule configuration: whether it runs, and at what severity it should report.
public struct RuleSettings: Codable, Equatable {
  public var enabled: Bool
  public var severity: Severity
  /// Free-form knobs a specific rule may read, such as a coverage drop threshold.
  public var options: [String: String]

  public init(
    enabled: Bool = true,
    severity: Severity = .error,
    options: [String: String] = [:]
  ) {
    self.enabled = enabled
    self.severity = severity
    self.options = options
  }
}

/// Top-level configuration, normally loaded from `.regressionguard.yml` or JSON at the root.
public struct Configuration: Codable, Equatable {
  public var rules: [String: RuleSettings]
  public var ignore: [String]
  public var testPaths: [String]
  /// A commit-message / PR-description marker that authorizes an otherwise-flagged change.
  public var approvalMarker: String

  public init(
    rules: [String: RuleSettings] = [:],
    ignore: [String] = [],
    testPaths: [String] = [],
    approvalMarker: String = "regression-guard:approve"
  ) {
    self.rules = rules
    self.ignore = ignore
    self.testPaths = testPaths
    self.approvalMarker = approvalMarker
  }

  public func settings(
    for ruleID: String,
    default defaultSettings: RuleSettings
  ) -> RuleSettings {
    rules[ruleID] ?? defaultSettings
  }

  public static var `default`: Self {
    Self(
      rules: [
        "disabled_or_skipped_test": RuleSettings(enabled: true, severity: .error),
        "weakened_assertion": RuleSettings(enabled: true, severity: .error),
        "behavior_deletion": RuleSettings(enabled: true, severity: .warning),
        "error_handling_collapse": RuleSettings(enabled: true, severity: .warning),
        "golden_master_drift": RuleSettings(enabled: true, severity: .warning),
        "coverage_regression": RuleSettings(enabled: true, severity: .error),
        "review_escape": RuleSettings(enabled: true, severity: .error),
        "enforcement_weakening": RuleSettings(enabled: true, severity: .error),
      ],
      ignore: ["**/.build/**", "**/Generated/**", "**/*.generated.swift"],
      testPaths: ["Tests/**", "**/*Tests.swift", "**/*Test.swift", "**/*Spec.swift"],
      approvalMarker: "regression-guard:approve"
    )
  }
}

/// Context shared with every rule while it evaluates a diff.
public struct RuleContext {
  public let configuration: Configuration
  public let pathClassifier: PathClassifier
  public let repository: GitRepository
  public let baseRef: String
  public let headRef: String
  /// The head commit message(s) in range, used to look for the approval marker.
  public let commitMessages: [String]

  public init(
    configuration: Configuration,
    pathClassifier: PathClassifier,
    repository: GitRepository,
    baseRef: String,
    headRef: String,
    commitMessages: [String]
  ) {
    self.configuration = configuration
    self.pathClassifier = pathClassifier
    self.repository = repository
    self.baseRef = baseRef
    self.headRef = headRef
    self.commitMessages = commitMessages
  }

  public var isApproved: Bool {
    let marker = configuration.approvalMarker.lowercased()
    return commitMessages.contains { $0.lowercased().contains(marker) }
  }
}
