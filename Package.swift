// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-notes-automation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotesAutomation", targets: ["NotesAutomation"]),
    ],
    targets: [
        .target(name: "NotesAutomation"),
        .testTarget(
            name: "NotesAutomationTests",
            dependencies: ["NotesAutomation"]
        ),
    ]
)
