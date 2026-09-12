// swift-tools-version: 6.0
import PackageDescription

// Harness for the "Parse performance budget" ticket. It is deliberately its own package rather
// than a target of the root one: it has to depend on swift-syntax to measure it, and
// RegressionGuardKit is dependency-free by decision. The version range matches the pin recorded in
// `SyntaxGrammar.pinnedAlignmentSeries`, and moves with it.
let package = Package(
  name: "parsebench",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax", "603.0.0"..<"604.0.0")
  ],
  targets: [
    .target(
      name: "ParseBenchCore",
      dependencies: [
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .executableTarget(name: "parsebench", dependencies: ["ParseBenchCore"]),
    .executableTarget(name: "spawnprobe", dependencies: ["ParseBenchCore"]),
  ],
  swiftLanguageModes: [.v6]
)
