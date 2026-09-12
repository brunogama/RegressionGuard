import Foundation
import Testing
@testable import RegressionGuardKit

@Suite("Configuration loader tests")
struct ConfigurationLoaderTests {

  @Test("falls back to default when no config file exists")
  func fallsBackToDefaultWhenNoConfigFileExists() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let config = ConfigurationLoader().load(fromDirectory: dir)
    #expect(config == Configuration.default)
  }

  @Test("parses YAML rules, ignore, and test paths")
  func parsesYAMLRulesIgnoreAndTestPaths() {
    let yaml = """
      version: 1
      approvalMarker: "custom:approve"
      rules:
        disabled_or_skipped_test:
          enabled: true
          severity: error
        production_code_deletion:
          enabled: false
          severity: warning
      ignore:
        - "**/Generated/**"
      testPaths:
        - "Tests/**"
      """
    let config = ConfigurationLoader.parseYAML(yaml)
    #expect(config != nil)
    #expect(config?.approvalMarker == "custom:approve")
    #expect(config?.rules["disabled_or_skipped_test"]?.enabled == true)
    #expect(config?.rules["disabled_or_skipped_test"]?.severity == .error)
    #expect(config?.rules["production_code_deletion"]?.enabled == false)
    #expect(config?.ignore == ["**/Generated/**"])
    #expect(config?.testPaths == ["Tests/**"])
  }

  @Test("parses json config")
  func parsesJSONConfig() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let json = """
      {
        "rules": { "disabled_or_skipped_test": { "enabled": true, "severity": "error", "options": {} } },
        "ignore": ["**/Generated/**"],
        "testPaths": ["Tests/**"],
        "approvalMarker": "custom:approve"
      }
      """
    try json.write(
      to: dir.appendingPathComponent(".regressionguard.json"),
      atomically: true,
      encoding: .utf8
    )

    let config = ConfigurationLoader().load(fromDirectory: dir)
    #expect(config.approvalMarker == "custom:approve")
    #expect(config.testPaths == ["Tests/**"])
  }
}
