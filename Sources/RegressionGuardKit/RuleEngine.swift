import Foundation

/// Runs every enabled rule over the unified evidence bundle.
public struct RuleEngine {
  /// Everything one run produced: the findings, plus the holes in the evidence they were judged
  /// on. A gap is reported rather than dropped, so a degraded run cannot read as a clean one.
  public struct Result: Equatable, Sendable {
    public let violations: [Violation]
    public let syntacticEvidenceGaps: [SyntaxEvidenceGap]
    /// The grammar the trees were parsed with, absent when the run had no parser.
    ///
    /// Carried on the result rather than the report because serialising it into the envelope
    /// belongs to Report version and compatibility, which owns the schema bump. The run still
    /// needs it here: an under-selected grammar is the one degradation the trees cannot reveal.
    public let syntaxGrammar: SyntaxGrammar?
    /// The severity each enabled rule reported at, keyed by rule ID.
    ///
    /// A run knows which families it actually asked; nothing downstream can reconstruct that from
    /// the findings, because a family that found nothing leaves none. Reported so a clean result
    /// can be told from an absent rule.
    public let ruleSeverities: [String: Severity]
    /// Rules configuration switched off, with the severity they would have reported at.
    ///
    /// Reported alongside the enabled ones so a deferred family is visibly deferred. Dropping it
    /// would make `enabled: false` - the deferral the upgrade note recommends - produce a report
    /// identical to a guard version that never had the rule.
    public let disabledRuleSeverities: [String: Severity]
    /// `true` when an approval marker stopped every rule from running.
    ///
    /// Without it an approved run is byte-shaped like a guard that has no rules: no findings, no
    /// rule list, exit zero. That is the same "absent reads as never present" ambiguity
    /// `ruleSeverities` exists to close, so the suppression says so rather than looking clean.
    public let isApproved: Bool

    public init(
      violations: [Violation],
      syntacticEvidenceGaps: [SyntaxEvidenceGap] = [],
      syntaxGrammar: SyntaxGrammar? = nil,
      ruleSeverities: [String: Severity] = [:],
      disabledRuleSeverities: [String: Severity] = [:],
      isApproved: Bool = false
    ) {
      self.violations = violations
      self.syntacticEvidenceGaps = syntacticEvidenceGaps
      self.syntaxGrammar = syntaxGrammar
      self.ruleSeverities = ruleSeverities
      self.disabledRuleSeverities = disabledRuleSeverities
      self.isApproved = isApproved
    }

    /// Every rule the run knew about, enabled or deferred, for the report.
    public func reportedRules(failOn threshold: Severity) -> [ReportedRule] {
      let enabled = ruleSeverities.map {
        ReportedRule(ruleID: $0.key, severity: $0.value, failOn: threshold, enabled: true)
      }
      let disabled = disabledRuleSeverities.map {
        ReportedRule(ruleID: $0.key, severity: $0.value, failOn: threshold, enabled: false)
      }
      return (enabled + disabled).sorted { $0.ruleID < $1.ruleID }
    }
  }

  public let rules: [Rule]
  /// Supplies parsed trees for the files rules declare they need. `nil` means this run cannot
  /// parse, and every declared file becomes an explicit gap rather than a silent pass.
  public let syntacticEvidenceProvider: SyntacticEvidenceProvider?

  public init(
    rules: [Rule] = Self.defaultRules,
    syntacticEvidenceProvider: SyntacticEvidenceProvider? = nil
  ) {
    self.rules = rules
    self.syntacticEvidenceProvider = syntacticEvidenceProvider
  }

  public static var defaultRules: [Rule] {
    [
      DisabledOrSkippedTestRule(),
      WeakenedAssertionRule(),
      ControlFlowDeletionRule(),
      UncheckedErrorPathRule(),
      // AST-only families. New rule IDs, so they ship advisory and no existing configuration
      // mentions them; promotion to blocking runs through the observer's calibration path.
      KnownIssueSuppressionRule(),
      ImplementationStubbedRule(),
      UnreachableAssertionRule(),
      GuardConfigurationWeakeningRule(),
      ReviewEscapeRule(),
      CoverageRegressionRule(),
      CharacterizationDriftRule(),
    ]
  }

  /// Compatibility entry point for callers that only have parsed file diffs.
  public func run(diff: [FileDiff], context: RuleContext) async -> [Violation] {
    await evaluate(diff: diff, context: context).violations
  }

  /// Entry point for callers that only have parsed file diffs and want the evidence gaps too.
  public func evaluate(diff: [FileDiff], context: RuleContext) async -> Result {
    let evidence = EvidenceBundle(
      fileDiffs: diff,
      commit: CommitEvidence(
        baseRef: context.baseRef,
        headRef: context.headRef,
        messages: context.commitMessages
      )
    )
    return await evaluate(evidence: evidence, context: context)
  }

  /// Evaluates every enabled rule against one canonical evidence bundle.
  public func run(evidence: EvidenceBundle, context: RuleContext) async -> [Violation] {
    await evaluate(evidence: evidence, context: context).violations
  }

  /// Evaluates every enabled rule, resolving the syntactic evidence they declared they need.
  public func evaluate(evidence: EvidenceBundle, context: RuleContext) async -> Result {
    guard !context.isApproved else { return Result(violations: [], isApproved: true) }

    let enabled = enabledRules(context: context)
    let resolved = resolvingSyntacticEvidence(in: evidence, for: enabled, context: context)
    let visibleEvidence = excludingIgnoredPaths(from: resolved, context: context)
    var violations: [Violation] = []

    for (rule, settings) in enabled {
      let evidenceForRule = type(of: rule).inspectsIgnoredPaths ? resolved : visibleEvidence
      var findings = await rule.evaluate(evidence: evidenceForRule, context: context)
      for index in findings.indices {
        findings[index].severity = settings.severity
      }
      violations.append(contentsOf: findings)
    }

    return Result(
      violations: violations,
      syntacticEvidenceGaps: resolved.syntax.gaps
        + resolved.syntax.grammarGaps(for: resolved.fileDiffs),
      syntaxGrammar: syntacticEvidenceProvider?.grammar,
      ruleSeverities: Dictionary(
        enabled.map { (type(of: $0.rule).ruleID, $0.settings.severity) },
        uniquingKeysWith: { _, last in last }
      ),
      disabledRuleSeverities: deferredRuleSeverities(context: context)
    )
  }

  /// The rules configuration leaves switched on, paired with the settings they report at.
  private func enabledRules(context: RuleContext) -> [(rule: Rule, settings: RuleSettings)] {
    rules.compactMap { rule in
      let ruleType = type(of: rule)
      let settings = configuredSettings(
        for: ruleType.ruleID,
        default: RuleSettings(enabled: true, severity: ruleType.defaultSeverity),
        context: context
      )
      return settings.enabled ? (rule, settings) : nil
    }
  }

  /// The rules configuration switched off, with the severity they would have reported at.
  private func deferredRuleSeverities(context: RuleContext) -> [String: Severity] {
    var deferred: [String: Severity] = [:]
    for rule in rules {
      let ruleType = type(of: rule)
      let settings = configuredSettings(
        for: ruleType.ruleID,
        default: RuleSettings(enabled: true, severity: ruleType.defaultSeverity),
        context: context
      )
      guard !settings.enabled else { continue }
      deferred[ruleType.ruleID] = settings.severity
    }
    return deferred
  }

  /// Collects every enabled rule's declared files and resolves them in one provider call.
  ///
  /// One call, not one per file: base-ref reads cost a subprocess each and dominate the run, so
  /// batching them is part of the contract rather than an optimization.
  private func resolvingSyntacticEvidence(
    in evidence: EvidenceBundle,
    for enabled: [(rule: Rule, settings: RuleSettings)],
    context: RuleContext
  ) -> EvidenceBundle {
    guard evidence.syntax.isEmpty else { return evidence }

    let visibleDiffs = evidence.fileDiffs.filter {
      !context.pathClassifier.isIgnored($0.displayPath)
    }
    var requests: [SyntacticEvidenceRequest] = []
    var seen: Set<SyntacticEvidenceRequest> = []
    for (rule, _) in enabled {
      let diffs = type(of: rule).inspectsIgnoredPaths ? evidence.fileDiffs : visibleDiffs
      for request in diffs.flatMap({ rule.syntacticEvidenceRequests(for: $0) })
      where seen.insert(request).inserted {
        requests.append(request)
      }
    }
    guard !requests.isEmpty else { return evidence }

    let provider = syntacticEvidenceProvider ?? UnavailableSyntacticEvidenceProvider()
    let resolved = provider.syntacticEvidence(for: requests)
    return evidence.withSyntacticEvidence(resolved.reconciled(with: requests))
  }

  private func configuredSettings(
    for ruleID: String,
    default defaultSettings: RuleSettings,
    context: RuleContext
  ) -> RuleSettings {
    if let settings = context.configuration.rules[ruleID] {
      return settings
    }
    let splitRuleIDs = ["behavior_deletion", "error_handling_collapse"]
    guard splitRuleIDs.contains(ruleID) else { return defaultSettings }
    return context.configuration.rules["production_code_deletion"] ?? defaultSettings
  }

  private func excludingIgnoredPaths(
    from evidence: EvidenceBundle,
    context: RuleContext
  ) -> EvidenceBundle {
    let visibleDiffs = evidence.fileDiffs.filter {
      !context.pathClassifier.isIgnored($0.displayPath)
    }
    let visiblePaths = Set(visibleDiffs.map(\.displayPath))
    let visibleContents = evidence.fileContents.filter { visiblePaths.contains($0.key) }
    let visiblePathEvidence = evidence.pathEvidence.filter { visiblePaths.contains($0.key) }
    return EvidenceBundle(
      fileDiffs: visibleDiffs,
      fileContents: visibleContents,
      pathEvidence: visiblePathEvidence,
      commit: evidence.commit,
      repository: evidence.repository,
      syntax: evidence.syntax.retainingPaths(visiblePaths)
    )
  }
}
