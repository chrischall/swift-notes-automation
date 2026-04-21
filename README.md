# NotesAutomation

[![CI](https://github.com/chrischall/swift-notes-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/chrischall/swift-notes-automation/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-notes-automation%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/chrischall/swift-notes-automation)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-notes-automation%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/chrischall/swift-notes-automation)

Swift library for driving Apple Notes.app on macOS. Wraps AppleScript
(via `NSAppleScript`) — Notes.app has no public Swift framework.

Platform: **macOS 14+**. Pure Swift 6 with strict concurrency. Zero
external dependencies.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chrischall/swift-notes-automation.git", from: "0.1.0"),
]
```

## Quickstart

```swift
import NotesAutomation

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

## API reference

### `NoteService`

The main entry point. Construct once, reuse across calls. All methods
are async and throw `AppleScriptError` or `NoteServiceError`.

| Method | Purpose |
|---|---|
| `list(limit:) -> [Note]` | Most-recently-modified notes |
| `search(query:limit:) -> [Note]` | Substring match against name OR body |
| `create(title:body:folder:) -> String` | Create a note; returns id |

### `Note`

```swift
id: String        // opaque Notes.app id
title: String     // name of note
snippet: String   // ~200 chars of body
folder: String    // containing folder name
```

### `AppleScriptRunner` / `NSAppleScriptRunner`

Protocol + production impl. Inject a fake in unit tests (see below).

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
import NotesAutomation

final class FakeRunner: AppleScriptRunner {
    var response = ""
    func run(source: String) async throws -> String { response }
}

let notes = NoteService(runner: FakeRunner())
```

## License

MIT. See [LICENSE](LICENSE).
