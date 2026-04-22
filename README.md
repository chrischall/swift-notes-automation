# NotesAutomation

[![CI](https://github.com/chrischall/swift-notes-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/chrischall/swift-notes-automation/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-notes-automation%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/chrischall/swift-notes-automation)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-notes-automation%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/chrischall/swift-notes-automation)

Swift library for driving Apple Notes.app on macOS. Two complementary
access paths:

- **`NoteService`** — AppleScript-backed. All CRUD (create, list,
  search, delete). Goes through Notes.app → CloudKit, so writes sync
  to iCloud automatically.
- **`NoteStoreReader`** — direct read-only SQLite access to
  `NoteStore.sqlite`. Roughly 100× faster than AppleScript for list
  and search. Requires Full Disk Access.

Platform: **macOS 14+**. Pure Swift 6 with strict concurrency. Zero
external dependencies (SQLite is via the system `SQLite3` module).

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chrischall/swift-notes-automation.git", from: "1.0.0"),
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

// Delete — permanent; bypasses the Recently Deleted folder
try await notes.delete(id: id)
```

### Fast read path

For list/search over large note libraries, `NoteStoreReader` reads
`NoteStore.sqlite` directly — no AppleScript round-trips, so listing a
thousand notes takes milliseconds:

```swift
let reader = try NoteStoreReader()
let notes = try await reader.list(limit: 50)
let hits  = try await reader.search(query: "groceries")
```

`NoteStoreReader` is **read-only** by design. Use `NoteService` for
create/delete — writes go through Notes.app so iCloud sync keeps
working. Requires Full Disk Access on macOS (see *Permissions*).

## API reference

### `NoteService`

AppleScript-backed CRUD. Construct once, reuse across calls. All
methods are async and throw `AppleScriptError` or `NoteServiceError`.

| Method | Purpose |
|---|---|
| `list(limit:) -> [Note]` | Most-recently-modified notes |
| `search(query:limit:) -> [Note]` | Substring match against name OR body |
| `create(title:body:folder:) -> String` | Create a note; returns id |
| `delete(id:)` | Permanently delete by id |

### `NoteStoreReader`

Direct read-only SQLite reader. Methods are async and throw
`NoteStoreReaderError`.

| Method | Purpose |
|---|---|
| `init(path:)` | Open `NoteStore.sqlite`. Defaults to standard location. |
| `list(limit:) -> [Note]` | Fast equivalent of `NoteService.list` |
| `search(query:limit:) -> [Note]` | Fast equivalent of `NoteService.search` |

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
- List recent notes (via `NoteService` or fast `NoteStoreReader`)
- Search by name/body substring (via either path)
- Create notes in any folder (folder created if missing)
- Delete notes by id

**Not supported (yet):**
- Update (Notes AppleScript supports it; happy to take a PR)
- Rich HTML content on read (plaintext snippet only; body is Core Data +
  protobuf)
- Attachments
- iCloud sync state

Full parsing of the protobuf-encoded body (`ZICCLOUDSYNCINGOBJECT.ZDATA`)
is still out of scope — the Ruby `apple_cloud_notes_parser` and Rust
`apple-notes-liberator` projects cover that territory.

## Permissions

- **`NoteService`** needs **Automation** access to Notes (System
  Settings → Privacy & Security → Automation → Your binary → Notes).
  Your binary should declare `NSAppleEventsUsageDescription` in its
  `Info.plist`.
- **`NoteStoreReader`** needs **Full Disk Access** (System Settings →
  Privacy & Security → Full Disk Access) so macOS lets your binary
  read `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`.
  The reader throws `NoteStoreReaderError.databaseNotAccessible` with a
  remediation hint if the grant is missing.

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
