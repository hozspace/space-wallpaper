// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SpaceCore", targets: ["SpaceCore"])],
    targets: [
        .target(name: "SpaceCore"),
        .testTarget(name: "SpaceCoreTests", dependencies: ["SpaceCore"]),
    ]
)
