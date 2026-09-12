import Foundation
import Testing

@Suite("Enforcement weakening end-to-end tests")
struct EnforcementWeakeningEndToEndTests {
  @Test("CLI blocks concrete guard-configuration weakenings")
  func cliBlocksConcreteGuardConfigurationWeakenings() throws {
    let repository = try ScratchRepository()
    defer { repository.remove() }

    try writeBaselineFiles(to: repository)
    let base = try repository.commit("Add guard configuration")

    try writeWeakenedFiles(to: repository)
    let head = try repository.commit("Relax guard configuration")

    let result = try repository.check(base: base, head: head)

    #expect(result.status == 1)
    #expect(result.output.contains("enforcement_weakening"))
  }

  private func writeBaselineFiles(to repository: ScratchRepository) throws {
    try repository.write(
      """
      rules:
        disabled_or_skipped_test:
          enabled: true
      """,
      to: ".regressionguard.yml"
    )
    try repository.write(
      """
      jobs:
        test:
          steps:
            - run: swift test
      """,
      to: ".github/workflows/ci.yml"
    )
    try repository.write("disabled_rules: []\n", to: ".swiftlint.yml")
    try repository.write(
      "let package = Package(targets: [.testTarget(name: \"Tests\")])\n",
      to: "Package.swift"
    )
  }

  private func writeWeakenedFiles(to repository: ScratchRepository) throws {
    try repository.write(
      """
      rules:
        disabled_or_skipped_test:
          enabled: false
      """,
      to: ".regressionguard.yml"
    )
    try repository.write(
      """
      jobs:
        test:
          steps:
            - run: swift build
      """,
      to: ".github/workflows/ci.yml"
    )
    try repository.write("disabled_rules:\n  - force_unwrapping\n", to: ".swiftlint.yml")
    try repository.write(
      "let package = Package(targets: [.target(name: \"Tests\")])\n",
      to: "Package.swift"
    )
  }
}
