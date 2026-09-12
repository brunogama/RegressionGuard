import XCTest
@testable import RegressionGuardKit

final class ConfigurationLoaderTests: XCTestCase {

  func testFallsBackToDefaultWhenNoConfigFileExists() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let config = ConfigurationLoader().load(fromDirectory: dir)
    XCTAssertEqual(config, Configuration.default)
  }

  func testParsesYAMLRulesIgnoreAndTestPaths() {
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
    XCTAssertNotNil(config)
    XCTAssertEqual(config?.approvalMarker, "custom:approve")
    XCTAssertEqual(config?.rules["disabled_or_skipped_test"]?.enabled, true)
    XCTAssertEqual(config?.rules["disabled_or_skipped_test"]?.severity, .error)
    XCTAssertEqual(config?.rules["production_code_deletion"]?.enabled, false)
    XCTAssertEqual(config?.ignore, ["**/Generated/**"])
    XCTAssertEqual(config?.testPaths, ["Tests/**"])
  }

  func testParsesJSONConfig() throws {
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
    XCTAssertEqual(config.approvalMarker, "custom:approve")
    XCTAssertEqual(config.testPaths, ["Tests/**"])
  }
}
