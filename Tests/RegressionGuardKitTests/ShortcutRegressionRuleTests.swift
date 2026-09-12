import Testing
@testable import RegressionGuardKit

@Suite("Shortcut regression rule tests")
struct ShortcutRegressionRuleTests {
  @Test("behavior deletion has its own rule identity")
  func behaviorDeletionHasItsOwnRuleIdentity() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Validator.swift",
      removed: [
        "    if !isValid { throw ValidationError.invalid }",
        "    guard let user else { throw AuthError.missingUser }",
        "    for item in items { try validate(item) }",
      ]
    )

    let findings = await ControlFlowDeletionRule().evaluate(
      fileDiff: diff,
      context: TestSupport.context()
    )

    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == ControlFlowDeletionRule.ruleID)
  }

  @Test("error handling collapse has its own rule identity")
  func errorHandlingCollapseHasItsOwnRuleIdentity() async {
    let diff = TestSupport.fileDiff(
      path: "Sources/Validator.swift",
      added: [
        "    let value = maybeValue!",
        "    } catch {}",
      ]
    )

    let findings = await UncheckedErrorPathRule().evaluate(
      fileDiff: diff,
      context: TestSupport.context()
    )

    #expect(findings.count == 2)
    #expect(findings.allSatisfy { $0.ruleID == UncheckedErrorPathRule.ruleID })
  }

  @Test("shortcut rules ignore test files")
  func shortcutRulesIgnoreTestFiles() async {
    let diff = TestSupport.fileDiff(
      path: "Tests/ValidatorTests.swift",
      removed: ["    if !isValid { throw ValidationError.invalid }"],
      added: ["    let value = maybeValue!"]
    )

    #expect(
      await ControlFlowDeletionRule().evaluate(
        fileDiff: diff,
        context: TestSupport.context()
      ).isEmpty
    )
    #expect(
      await UncheckedErrorPathRule().evaluate(
        fileDiff: diff,
        context: TestSupport.context()
      ).isEmpty
    )
  }
  @Test("legacy production configuration disables split detectors")
  func legacyProductionConfigurationDisablesSplitDetectors() async {
    let configuration = Configuration(
      rules: [ProductionCodeDeletionRule.ruleID: RuleSettings(enabled: false)]
    )
    let diff = TestSupport.fileDiff(
      path: "Sources/Validator.swift",
      added: ["    let value = maybeValue!"]
    )

    let findings = await RuleEngine().run(
      diff: [diff],
      context: TestSupport.context(configuration: configuration)
    )

    #expect(
      !findings.contains {
        $0.ruleID == ControlFlowDeletionRule.ruleID
          || $0.ruleID == UncheckedErrorPathRule.ruleID
      }
    )
  }
  @Test("ignored changed paths produce a review-escape finding")
  func ignoredChangedPathsProduceReviewEscapeFinding() async {
    let configuration = Configuration(ignore: ["Hidden/**"])

    let diff = TestSupport.fileDiff(
      path: "Hidden/GeneratedValidator.swift",
      added: ["func validate() {}"]
    )

    let findings = await RuleEngine().run(
      diff: [diff],
      context: TestSupport.context(configuration: configuration)
    )

    #expect(findings.map(\.ruleID) == [ReviewEscapeRule.ruleID])
  }

  @Test("default engine keeps the configured rule families")
  func defaultEngineKeepsConfiguredRuleFamilies() {
    let ruleIDs = Set(RuleEngine.defaultRules.map { type(of: $0).ruleID })
    let expected = Set([
      "disabled_or_skipped_test",
      "weakened_assertion",
      "behavior_deletion",
      "error_handling_collapse",
      "golden_master_drift",
      "coverage_regression",
      "enforcement_weakening",
      "review_escape",
      // AST-only families, advisory by default.
      "known_issue_suppression",
      "implementation_stubbed",
      "unreachable_assertion",
    ])

    #expect(ruleIDs == expected)
  }
}
