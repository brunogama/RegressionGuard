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
    .library(name: "GoldenMaster", targets: ["GoldenMaster"])
  ],
  targets: [
    .target(
      name: "GoldenMaster",
      dependencies: []
    ),
    .testTarget(
      name: "GoldenMasterTests",
      dependencies: ["GoldenMaster"],
      resources: [.copy("__GoldenMasters__")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
