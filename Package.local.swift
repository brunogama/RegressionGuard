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
    // Vendored the same way and for the same reasons as swift-syntax below: a bare repository
    // committed into this one, referenced as local source control so the resolver enforces the
    // version and records it, and named only here so it never takes the `commander` identity in a
    // consumer's dependency graph.
    .package(url: "Vendor/Commander.git", from: "0.2.4"),
    // A bare git repository committed into this one, not a path dependency. The distinction is the
    // whole point: a path dependency gets no `Package.resolved` entry and no version, so the
    // checkout would be its own pin. Referenced as local source control, the resolver reads the
    // tags and enforces the same range `Package.swift` declares - a vendored copy off the pinned
    // series fails resolution instead of quietly building the wrong grammar.
    //
    // The path is relative, so the clone carries everything an offline build needs. It is declared
    // only here: naming it in `Package.swift` would give it the identity `swift-syntax` in every
    // consumer's graph and silently replace the swift-syntax they asked for.
    .package(url: "Vendor/swift-syntax.git", "603.0.0"..<"604.0.0"),
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
