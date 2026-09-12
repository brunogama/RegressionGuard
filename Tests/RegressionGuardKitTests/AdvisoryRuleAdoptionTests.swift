import Foundation
import Testing

@testable import RegressionGuardKit

/// Adoption and deferral are the only things an upgrading repository has to do, so both are
/// ordinary configuration and both are pinned here. The generated config is part of that
/// contract: a repository that runs `regression-guard init` should see the choice rather than
/// discover the families later.
@Suite("Advisory rule adoption tests")
struct AdvisoryRuleAdoptionTests {
  private static let advisoryRuleIDs = [
    "known_issue_suppression", "implementation_stubbed", "unreachable_assertion",
  ]

  @Test("the advisory families report at a severity the default threshold does not block on")
  func advisoryFamiliesDoNotBlockByDefault() {
    let defaultThreshold = Severity.error
    let advisory = RuleEngine.defaultRules
      .filter { Self.advisoryRuleIDs.contains(type(of: $0).ruleID) }

    #expect(advisory.count == Self.advisoryRuleIDs.count)
    for rule in advisory {
      #expect(type(of: rule).defaultSeverity < defaultThreshold)
    }
  }

  @Test("a repository defers a family by disabling it, and the engine stops running it")
  func deferringARuleRemovesIt() async {
    let configuration = Configuration(
      rules: ["implementation_stubbed": RuleSettings(enabled: false, severity: .warning)]
    )
    let engine = RuleEngine()
    let result = await engine.evaluate(
      diff: [],
      context: TestSupport.context(configuration: configuration)
    )

    #expect(result.ruleSeverities["implementation_stubbed"] == nil)
    #expect(result.ruleSeverities["weakened_assertion"] != nil)
  }

  @Test("a repository adopts a family by raising its severity, and the run reports it blocking")
  func adoptingARuleMakesItBlocking() async throws {
    let configuration = Configuration(
      rules: ["implementation_stubbed": RuleSettings(enabled: true, severity: .error)]
    )
    let engine = RuleEngine()
    let result = await engine.evaluate(
      diff: [],
      context: TestSupport.context(configuration: configuration)
    )
    let severity = try #require(result.ruleSeverities["implementation_stubbed"])

    #expect(severity == .error)
    #expect(ReportedRule(ruleID: "x", severity: severity, failOn: .error).blocking)
  }

  @Test("the generated configuration names every advisory family, so none is discovered late")
  func generatedConfigurationNamesTheAdvisoryFamilies() throws {
    let yaml = try #require(Self.generatedConfiguration())

    for ruleID in Self.advisoryRuleIDs {
      #expect(yaml.contains(ruleID))
    }
  }

  /// The default config the CLI writes. Read from the CLI's own constant when the test target can
  /// see it, and skipped rather than faked when it cannot.
  private static func generatedConfiguration() -> String? {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/regression-guard/RegressionGuardCommand.swift")
    return try? String(contentsOf: url, encoding: .utf8)
  }
}
