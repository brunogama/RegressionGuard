// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The CLI, kept out of the published package so its dependencies stay out of every consumer's
// dependency graph. A nested package is resolved by nobody: SwiftPM resolves a package from a
// repository root, so this manifest and everything it pulls in is invisible to anyone depending on
// RegressionGuard. Verified against the same mechanism upstream - a consumer of swift-syntax does
// not resolve swift-argument-parser, which its nested `SwiftParserCLI` package depends on.
//
// Set `REGRESSIONGUARD_OFFLINE` to build against the repositories vendored under `Vendor/` instead
// of fetching from upstream. An environment-driven manifest would be wrong in a published package,
// because the graph would depend on the reader's shell; here no consumer ever reads this file.
let offline = ProcessInfo.processInfo.environment["REGRESSIONGUARD_OFFLINE"] != nil

// Pinned to one alignment series, not a floor. Each series is a new major, so `from:` cannot float
// across them, and an under-selected parser cannot represent newer syntax - it reads it into an
// unexpected node and the rule written to catch it stops firing. The series is decided in
// `SyntaxGrammar.pinnedAlignmentSeries`; raise both bounds with it.
let syntaxRange = Version(603, 0, 0)..<Version(604, 0, 0)

let package = Package(
  name: "RegressionGuardCLI",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "regression-guard", targets: ["regression-guard"]),
    .executable(
      name: "regression-guard-observer",
      targets: ["regression-guard-observer"]
    ),
    // `swift package regression-guard` command plugin.
    .plugin(name: "RegressionGuardPlugin", targets: ["RegressionGuardPlugin"]),
  ],
  dependencies: [
    // Named explicitly so the identity does not depend on what this repository's directory is
    // called - a path dependency otherwise takes its identity from the folder name, which breaks
    // in a worktree, a fork, or any clone the user renamed.
    .package(name: "RegressionGuard", path: "..")
  ],
  targets: [
    // Owns swift-syntax so RegressionGuardKit does not have to.
    .target(
      name: "RegressionGuardSyntax",
      dependencies: [
        .product(name: "RegressionGuardKit", package: "RegressionGuard"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    // The binding and help layer Commander does not ship: its property wrappers register metadata
    // but never receive parsed values, and it renders no help at all.
    .target(
      name: "RegressionGuardCommandLine",
      dependencies: [.product(name: "Commander", package: "Commander")]
    ),
    .executableTarget(
      name: "regression-guard",
      dependencies: [
        .product(name: "RegressionGuardKit", package: "RegressionGuard"),
        "RegressionGuardSyntax",
        "RegressionGuardCommandLine",
        .product(name: "Commander", package: "Commander"),
      ]
    ),
    .executableTarget(
      name: "regression-guard-observer",
      dependencies: [
        .product(name: "RegressionGuardKit", package: "RegressionGuard"),
        .product(name: "RegressionGuardObserver", package: "RegressionGuard"),
        "RegressionGuardCommandLine",
        .product(name: "Commander", package: "Commander"),
      ]
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
      name: "RegressionGuardSyntaxTests",
      dependencies: [
        .product(name: "RegressionGuardKit", package: "RegressionGuard"),
        "RegressionGuardSyntax",
      ]
    ),
    .testTarget(
      name: "RegressionGuardCLITests",
      dependencies: [
        .product(name: "RegressionGuardKit", package: "RegressionGuard"),
        "regression-guard",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)

// Vendored as bare repositories committed under `Vendor/`, referenced as local source control
// rather than as paths. A `.package(path:)` gets no `Package.resolved` entry and no version, so the
// directory would be its own pin; as source control the resolver reads the tags and enforces the
// same versions the online branch declares.
package.dependencies +=
  offline
  ? [
    .package(url: "Vendor/swift-syntax.git", syntaxRange),
    .package(url: "Vendor/Commander.git", from: "0.2.4"),
  ]
  : [
    .package(url: "https://github.com/swiftlang/swift-syntax", syntaxRange),
    .package(url: "https://github.com/steipete/Commander", from: "0.2.4"),
  ]

// CI's strictness, carried by the manifest rather than passed on the command line.
// `swift build -Xswiftc -warnings-as-errors` reaches every target it compiles, including the
// dependencies, and SwiftPM only suppresses warnings for dependencies it fetched itself - so
// offline, where they resolve from local repositories, their own deprecations would fail a build
// this repository cannot fix. Scoped here, the flags mean what CI means by them: our code compiles
// warning-free. `.unsafeFlags` is safe in this manifest and only this one, because no consumer
// resolves a nested package.
for target in package.targets where target.type != .plugin {
  target.swiftSettings =
    (target.swiftSettings ?? []) + [
      .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"])
    ]
}
