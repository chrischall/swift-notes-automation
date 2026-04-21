# AppleNotesKit

Swift library for driving Apple Notes.app on macOS. Wraps AppleScript
(via `NSAppleScript`) — Notes.app has no public Swift framework.

Platform: macOS 14+. Pure Swift 6 with strict concurrency. Zero
external dependencies.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chrischall/AppleNotesKit.git", from: "0.1.0"),
]
```

## Quickstart

```swift
import AppleNotesKit

let notes = NoteService(runner: NSAppleScriptRunner())

// Recent notes
let recent = try await notes.list(limit: 10)
for note in recent {
    print("\(note.title) [\(note.folder)]: \(note.snippet)")
}

// Search — matches name OR body, case-insensitive
let groceries = try await notes.search(query: "milk")

// Create — folder is auto-created if it doesn't exist
let id = try await notes.create(
    title: "Weekly plan",
    body: "- Ship release\n- Review PRs",
    folder: "Work"
)
```

## Capabilities and limits

**Supported:**
- List recent notes
- Search by name/body substring
- Create notes in any folder (folder created if missing)

**Not supported (yet):**
- Update/delete (Notes AppleScript supports both; happy to take a PR)
- Rich HTML content (plaintext in, HTML-wrapped title on create)
- iCloud sync state
- Reading per-note attachments

Anything that requires parsing Notes's Core Data + protobuf-encoded
body storage (`~/Library/Group Containers/group.com.apple.notes/
NoteStore.sqlite`) is out of scope — the Ruby `apple_cloud_notes_parser`
and Rust `apple-notes-liberator` projects cover that territory.

## Permissions

The calling process needs **Automation** for Notes (System Settings →
Privacy & Security → Automation → Your binary → Notes). Your binary
should declare `NSAppleEventsUsageDescription` in its `Info.plist`.

## Testing

`AppleScriptRunner` is a public protocol, so tests can inject a fake:

```swift
import AppleNotesKit

final class FakeRunner: AppleScriptRunner {
    var response = ""
    func run(source: String) async throws -> String { response }
}

let notes = NoteService(runner: FakeRunner())
```

## License

MIT. See [LICENSE](LICENSE).
