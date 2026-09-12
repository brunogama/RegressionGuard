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
    .library(name: "GoldenMaster", targets: ["GoldenMaster"]),
    .library(name: "RegressionGuardKit", targets: ["RegressionGuardKit"]),
    .executable(name: "regression-guard", targets: ["regression-guard"]),
    .executable(
      name: "regression-guard-observer",
      targets: ["regression-guard-observer"]
    ),
    .plugin(name: "RegressionGuardPlugin", targets: ["RegressionGuardPlugin"]),
  ],
  dependencies: [
    .package(path: "../Commander"),
    // A path dependency gets no `Package.resolved` entry, so this checkout's own tag is the entire
    // pin - there is no resolver to enforce the range `Package.swift` declares. It must sit on the
    // series `SyntaxGrammar.pinnedAlignmentSeries` names, and
    // `scripts/prepare-offline-validation.py` refuses to build a copy when it does not.
    .package(path: "../swift-syntax"),
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
