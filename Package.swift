// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OTrainTimer",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "OTrainTimer", targets: ["OTrainTimer"])],
  targets: [
    .executableTarget(name: "OTrainTimer"),
    .testTarget(name: "OTrainTimerTests", dependencies: ["OTrainTimer"]),
  ]
)
