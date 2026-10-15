// swift-tools-version: 6.0
import PackageDescription

// Bridge to ERiC, the ELSTER client library. macOS only: the app adds it with platformFilters: [macOS].
// The ERiC dylibs are not linked; CEric dlopen()s them at runtime (see CEric.h).
let package = Package(
    name: "EricKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "EricKit", targets: ["EricKit"]),
    ],
    targets: [
        .target(name: "CEric"),
        .target(name: "EricKit", dependencies: ["CEric"]),
        .testTarget(name: "EricKitTests", dependencies: ["EricKit"]),
    ]
)
