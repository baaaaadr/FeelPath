// swift-tools-version: 5.9
// FeelPathCore — platform-free logic (no ARKit, no Core Haptics) so it can be unit-tested
// anywhere, including Linux CI and Docker on Windows.
import PackageDescription

let package = Package(
    name: "FeelPathCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FeelPathCore", targets: ["FeelPathCore"]),
    ],
    targets: [
        .target(name: "FeelPathCore"),
        .testTarget(name: "FeelPathCoreTests", dependencies: ["FeelPathCore"]),
    ]
)
