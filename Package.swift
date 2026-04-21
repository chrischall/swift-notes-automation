// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleNotesKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppleNotesKit", targets: ["AppleNotesKit"]),
    ],
    targets: [
        .target(name: "AppleNotesKit"),
        .testTarget(
            name: "AppleNotesKitTests",
            dependencies: ["AppleNotesKit"]
        ),
    ]
)
