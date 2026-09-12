// swift-tools-version: 6.0
import PackageDescription

// The published package: libraries only, and deliberately no dependencies.
//
// SwiftPM resolves a consumer's whole package graph regardless of which product that consumer
// uses, so a dependency-free target inside a package that has dependencies is not a
// dependency-free consumer. Measured before this split, a project wanting only `GoldenMaster` for
// snapshot tests fetched 80,542 objects and carried 13.5 MiB of checkouts for a CLI it never
// built. The CLI and everything it depends on now live in `RegressionGuardCLI/`, a nested
// package no consumer resolves.
//
// The `swift package regression-guard` plugin returns here once a release exists to point a
// `.binaryTarget` at; see `.scratch/tickets/25-nested-cli-package-layout.md`. Until then it lives
// in `RegressionGuardCLI/`, where it works for anyone building from a clone.
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
    .library(name: "RegressionGuardObserver", targets: ["RegressionGuardObserver"]),
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
    .target(
      name: "RegressionGuardObserver",
      dependencies: ["RegressionGuardKit"]
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
      name: "RegressionGuardObserverTests",
      dependencies: [
        "RegressionGuardKit",
        "RegressionGuardObserver",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
