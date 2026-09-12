import Testing
@testable import RegressionGuardKit

@Suite("Path classifier tests")
struct PathClassifierTests {
  @Test("double-star directory prefix matches root and nested paths")
  func doubleStarDirectoryPrefixMatchesRootAndNestedPaths() {
    #expect(PathClassifier.matches(pattern: "**/Generated/**", path: "Generated/Output.swift"))
    #expect(
      PathClassifier.matches(
        pattern: "**/Generated/**",
        path: "Sources/Generated/Output.swift"
      )
    )
  }
}
