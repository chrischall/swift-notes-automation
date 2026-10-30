// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-notes-automation",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NotesAutomation", targets: ["NotesAutomation"]),
    ],
    targets: [
        .target(
            name: "NotesAutomation",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "NotesAutomationTests",
            dependencies: ["NotesAutomation"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

/// Swift 6 language mode (complete strict concurrency) plus upcoming
/// features that tighten the source without changing runtime behaviour.
var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
