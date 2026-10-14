// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrotBooksKit",
    defaultLocalization: "en",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "BrotBooksKit", targets: ["BrotBooksKit"]),
    ],
    targets: [
        .target(name: "BrotBooksKit"),
        .testTarget(
            name: "BrotBooksKitTests",
            dependencies: ["BrotBooksKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
