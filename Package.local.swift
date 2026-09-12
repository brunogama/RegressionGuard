// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GoldenMasterSwift",
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
    .package(path: "../swift-argument-parser")
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
    .executableTarget(
      name: "regression-guard",
      dependencies: [
        "RegressionGuardKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
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
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
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
      name: "RegressionGuardObserverTests",
      dependencies: [
        "RegressionGuardKit",
        "RegressionGuardObserver",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
