import Testing
@testable import RegressionGuardKit

@Suite("Shortcut regression rule tests")
struct ShortcutRegressionRuleTests {
  @Test("behavior deletion has its own rule identity")
  func behaviorDeletionHasItsOwnRuleIdentity() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Validator.swift",
      removed: [
        "    if !isValid { throw ValidationError.invalid }",
        "    guard let user else { throw AuthError.missingUser }",
        "    for item in items { try validate(item) }",
      ]
    )

    let findings = ControlFlowDeletionRule().evaluate(
      fileDiff: diff,
      context: TestSupport.context()
    )

    #expect(findings.count == 1)
    #expect(findings.first?.ruleID == ControlFlowDeletionRule.ruleID)
  }

  @Test("error handling collapse has its own rule identity")
  func errorHandlingCollapseHasItsOwnRuleIdentity() {
    let diff = TestSupport.fileDiff(
      path: "Sources/Validator.swift",
      added: [
        "    let value = maybeValue!",
        "    } catch {}",
      ]
    )

    let findings = UncheckedErrorPathRule().evaluate(
      fileDiff: diff,
      context: TestSupport.context()
    )

    #expect(findings.count == 2)
    #expect(findings.allSatisfy { $0.ruleID == UncheckedErrorPathRule.ruleID })
  }

  @Test("shortcut rules ignore test files")
  func shortcutRulesIgnoreTestFiles() {
    let diff = TestSupport.fileDiff(
      path: "Tests/ValidatorTests.swift",
      removed: ["    if !isValid { throw ValidationError.invalid }"],
      added: ["    let value = maybeValue!"]
    )

    #expect(
      ControlFlowDeletionRule().evaluate(
        fileDiff: diff,
        context: TestSupport.context()
      ).isEmpty
    )
    #expect(
      UncheckedErrorPathRule().evaluate(
        fileDiff: diff,
        context: TestSupport.context()
      ).isEmpty
    )
  }
  @Test("legacy production configuration disables split detectors")
  func legacyProductionConfigurationDisablesSplitDetectors() {
    let configuration = Configuration(
      rules: [ProductionCodeDeletionRule.ruleID: RuleSettings(enabled: false)]
    )
    let diff = TestSupport.fileDiff(
      path: "Sources/Validator.swift",
      added: ["    let value = maybeValue!"]
    )

    let findings = RuleEngine().run(
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
  func ignoredChangedPathsProduceReviewEscapeFinding() {
    let configuration = Configuration(ignore: ["Hidden/**"])

    let diff = TestSupport.fileDiff(
      path: "Hidden/GeneratedValidator.swift",
      added: ["func validate() {}"]
    )

    let findings = RuleEngine().run(
      diff: [diff],
      context: TestSupport.context(configuration: configuration)
    )

    #expect(findings.map(\.ruleID) == [ReviewEscapeRule.ruleID])
  }

  @Test("default engine keeps the configured eight rule families")
  func defaultEngineKeepsConfiguredEightRuleFamilies() {
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
    ])

    #expect(ruleIDs == expected)
  }
}
