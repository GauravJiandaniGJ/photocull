// swift-tools-version:5.9
import PackageDescription

// Pure Swift. No UIKit / Vision / PhotoKit / SwiftData imports anywhere in this package:
// everything here runs under `swift test` on the Mac with synthetic metrics.
let package = Package(
    name: "PhotoCullCore",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [
        .library(name: "PhotoCullCore", targets: ["PhotoCullCore"]),
    ],
    targets: [
        .target(
            name: "PhotoCullCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "PhotoCullCoreTests",
            dependencies: ["PhotoCullCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
