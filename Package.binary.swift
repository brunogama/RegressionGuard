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
    .library(
      name: "RegressionGuardObserver",
      targets: ["RegressionGuardObserver"]
    ),
    .plugin(name: "RegressionGuardPlugin", targets: ["RegressionGuardPlugin"]),
  ],
  targets: [
    .binaryTarget(
      name: "GoldenMaster",
      path: "Artifacts/GoldenMaster.xcframework"
    ),
    .binaryTarget(
      name: "RegressionGuardKit",
      path: "Artifacts/RegressionGuardKit.xcframework"
    ),
    .binaryTarget(
      name: "RegressionGuardObserver",
      path: "Artifacts/RegressionGuardObserver.xcframework"
    ),
    .binaryTarget(
      name: "RegressionGuardCLI",
      path: "Artifacts/regression-guard.artifactbundle"
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
      dependencies: ["RegressionGuardCLI"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
