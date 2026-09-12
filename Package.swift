// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RegressionGuard",
  platforms: [
    .macOS(.v14),
    .iOS(.v15),
    .tvOS(.v15),
    .watchOS(.v8),
  ],
  products: [
    // Link into any test target to record/compare golden-master snapshots.
    .library(name: "GoldenMaster", targets: ["GoldenMaster"]),
    // The detection engine, usable as a library (e.g. from a custom CLI or plugin).
    .library(name: "RegressionGuardKit", targets: ["RegressionGuardKit"]),
    // The CI-facing command line tool.
    .executable(name: "regression-guard", targets: ["regression-guard"]),
    .executable(
      name: "regression-guard-observer",
      targets: ["regression-guard-observer"]
    ),
    // `swift package regression-guard` command plugin.
    .plugin(name: "RegressionGuardPlugin", targets: ["RegressionGuardPlugin"]),
  ],
  dependencies: [
    // Replaces swift-argument-parser. Pre-1.0, so `from:` admits 0.2.x only; a 0.3 would be a
    // breaking release and is a decision rather than a resolver outcome.
    .package(url: "https://github.com/steipete/Commander", from: "0.2.4"),
    // Pinned to one alignment series, not a floor. Each series is a new major, so `from:` cannot
    // float across them, and an under-selected parser cannot represent newer syntax - it reads it
    // into an unexpected node and the rule written to catch it stops firing. The series is decided
    // in `SyntaxGrammar.pinnedAlignmentSeries`; raise both bounds with it.
    .package(url: "https://github.com/swiftlang/swift-syntax", "603.0.0"..<"604.0.0"),
  ],
  targets: [
    .target(
      name: "GoldenMaster",
      dependencies: []
    ),
    .target(
      name: "RegressionGuardKit",
      dependencies: []
    ),
    // Owns swift-syntax so RegressionGuardKit does not have to. Only the CLI depends on it,
    // because `Package.binary.swift` ships RegressionGuardKit as an XCFramework and a binary
    // target cannot declare package dependencies.
    // The binding and help layer Commander does not ship: its property wrappers register metadata
    // but never receive parsed values, and it renders no help at all. Shared so both executables
    // fail and describe themselves identically.
    .target(
      name: "RegressionGuardCommandLine",
      dependencies: [.product(name: "Commander", package: "Commander")]
    ),
    .target(
      name: "RegressionGuardSyntax",
      dependencies: [
        "RegressionGuardKit",
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .executableTarget(
      name: "regression-guard",
      dependencies: [
        "RegressionGuardKit",
        "RegressionGuardSyntax",
        "RegressionGuardCommandLine",
        .product(name: "Commander", package: "Commander"),
      ]
    ),
    .target(
      name: "RegressionGuardObserver",
      dependencies: ["RegressionGuardKit"],
      path: "Sources/RegressionGuard/Observer"
    ),
    .executableTarget(
      name: "regression-guard-observer",
      dependencies: [
        "RegressionGuardObserver",
        "RegressionGuardCommandLine",
        .product(name: "Commander", package: "Commander"),
      ],
      path: "Sources/RegressionGuard/ObserverCLI"
    ),
    .plugin(
      name: "RegressionGuardPlugin",
      capability: .command(
        intent: .custom(
          verb: "regression-guard",
          description:
            "Runs the regression-guard anti-cheating checks against your working changes."
        ),
        permissions: []
      ),
      dependencies: ["regression-guard"]
    ),
    .testTarget(
      name: "GoldenMasterTests",
      dependencies: ["GoldenMaster"],
      resources: [.copy("__GoldenMasters__")]
    ),
    .testTarget(
      name: "RegressionGuardKitTests",
      dependencies: ["RegressionGuardKit"]
    ),
    .testTarget(
      name: "RegressionGuardSyntaxTests",
      dependencies: [
        "RegressionGuardKit",
        "RegressionGuardSyntax",
      ]
    ),
    .testTarget(
      name: "RegressionGuardObserverTests",
      dependencies: [
        "RegressionGuardKit",
        "RegressionGuardObserver",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
