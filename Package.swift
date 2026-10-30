// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-notes-automation",
    platforms: [.macOS("27.2")],
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
/// `InternalImportsByDefault` makes imports internal: files whose public
/// API names Foundation types say `public import Foundation`.
///
/// `NonisolatedNonsendingByDefault` is the one that changes runtime
/// behaviour: a nonisolated `async` function now runs on its caller's
/// actor. Anything that must leave that actor is marked `@concurrent` —
/// see `AppleScriptRunner.run(source:)`.
var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    ]
}
