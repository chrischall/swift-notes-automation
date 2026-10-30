# NotesAutomation

[![CI](https://github.com/chrischall/swift-notes-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/chrischall/swift-notes-automation/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-notes-automation%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/chrischall/swift-notes-automation)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-notes-automation%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/chrischall/swift-notes-automation)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Swift library for driving Apple Notes.app on macOS. Two complementary
access paths:

- **`NoteService`** — AppleScript-backed. Full read/write surface:
  `list`, `search`, `get` (untruncated body), `folders`, `create`,
  `update`, `delete`. Goes through Notes.app → CloudKit, so writes sync
  to iCloud automatically.
- **`NoteStoreReader`** — direct read-only SQLite access to
  `NoteStore.sqlite`. Roughly 100× faster than AppleScript for list,
  search, and folder enumeration. Requires Full Disk Access.

`list`/`search` return a truncated `Note.snippet` for scannable results
— for search, the snippet is windowed around the first body match rather
than blindly taken from the top; `get(id:)` returns the note's
**complete, untruncated** body as a `NoteDetail` — both plain text and
HTML, plus creation/modification dates. `bodyPage(_:offset:maxChars:)`
and `matchExcerpt(query:in:maxLength:)` are pure helpers for paging a
long body and re-anchoring a preview around a match.

Platform: **macOS 27.2+** (Swift 6.4 toolchain, Xcode 27+). Pure Swift 6 with strict concurrency. Zero
external dependencies (SQLite is via the system `SQLite3` module).

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chrischall/swift-notes-automation.git", from: "3.0.0"),
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

// Search — matches title OR plain-text body (not HTML markup), case-insensitive
let groceries = try await notes.search(query: "milk")

// Page through a large library
let page2 = try await notes.list(limit: 20, offset: 20)

// Get — the note's COMPLETE body (never truncated), plain + HTML + dates
let full = try await notes.get(id: recent[0].id)
print(full.plainText)   // untruncated
print(full.html)        // Notes.app rich HTML
print(full.modificationDate as Any)

// Folders — enumerate for browsing
let folderNames = try await notes.folders()

// Create — folder is auto-created if it doesn't exist
let id = try await notes.create(
    title: "Weekly plan",
    body: "- Ship release\n- Review PRs",
    folder: "Work"
)

// Update — edit title/body and/or move to another folder in place
try await notes.update(id: id, title: "Weekly plan (v2)", folder: "Archive")

// Delete — Notes.app moves it to Recently Deleted (recoverable there)
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
create/update/delete — writes go through Notes.app so iCloud sync keeps
working. Requires Full Disk Access on macOS (see *Permissions*).

## API reference

### `NoteService`

AppleScript-backed CRUD. Construct once, reuse across calls. All
methods are async and typed `throws(NotesError)`, so `catch` blocks get a
`NotesError` without casting:

| `NotesError` case | Meaning |
|---|---|
| `.invalidInput(String)` | Empty id/title, or an update with nothing to change. No AppleScript ran |
| `.scriptFailure(String)` | The script ran but its output couldn't be parsed |
| `.appleScript(.runtime(String))` | Notes.app not running, Automation denied, or no note with that id |
| `.appleScript(.compile(String))` | The runner couldn't compile the script |

```swift
do {
    let note = try await notes.get(id: id)
} catch .appleScript(.runtime(let message)) {
    print("Notes said no: \(message)")
} catch {
    print(error.localizedDescription)   // error is NotesError
}
```

| Method | Purpose |
|---|---|
| `list(limit:offset:) -> [Note]` | Most-recently-modified notes |
| `search(query:limit:offset:) -> [Note]` | Case-insensitive substring match against title OR plain-text body (not the HTML, so tag/attribute text never matches) |
| `get(id:) -> NoteDetail` | One note's complete body (plain text + HTML) and dates. An unknown id throws `NotesError.appleScript(.runtime(_))` |
| `folders() -> [String]` | Folder names |
| `create(title:body:folder:) -> String` | Create a note; returns id |
| `update(id:title:body:folder:)` | Change title, body and/or folder in place |
| `delete(id:)` | Delete by id — Notes.app moves the note to Recently Deleted |

### `NoteStoreReader`

Direct read-only SQLite reader. Methods are async and throw
`NoteStoreReaderError`.

| Method | Purpose |
|---|---|
| `init(path:)` | Open `NoteStore.sqlite`. Defaults to standard location. |
| `list(limit:offset:) -> [Note]` | Fast equivalent of `NoteService.list` |
| `search(query:limit:offset:) -> [Note]` | Fast equivalent of `NoteService.search` |
| `folders() -> [String]` | Folder names, excluding Recently Deleted |

### `Note`

```swift
id: String        // opaque Notes.app id
title: String     // name of note
snippet: String   // ~350-char preview (search: anchored at the match)
folder: String    // containing folder name
```

### `AppleScriptRunner` / `NSAppleScriptRunner`

Protocol + production impl. `run(source:)` is typed
`throws(AppleScriptError)`. Inject a fake in unit tests (see below).

## Capabilities and limits

**Supported:**
- List recent notes (via `NoteService` or fast `NoteStoreReader`)
- Search by title/plain-text-body substring (via either path; `NoteStoreReader` matches the stored snippet)
- Read one note's full body, as plain text and Notes.app HTML (`NoteService.get`)
- List folders
- Create notes in any folder (folder created if missing)
- Update a note's title, body and/or folder
- Delete notes by id (they go to Recently Deleted, like deleting in the app)

**Not supported (yet):**
- Rich content from `NoteStoreReader` (it returns the stored plain-text
  snippet; the full body there is Core Data + protobuf — use
  `NoteService.get` for the full body)
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

struct FakeRunner: AppleScriptRunner {
    var response = ""
    func run(source: String) async throws(AppleScriptError) -> String { response }
}

let notes = NoteService(runner: FakeRunner())
```

## Migrating to 3.0 (typed throws)

3.0 makes the `NoteService` error contract explicit. Every method is now
`throws(NotesError)`, and the `AppleScriptRunner` requirement is
`throws(AppleScriptError)`.

- **`NoteServiceError` is now `NotesError`.** The `.invalidInput` and
  `.scriptFailure` cases are unchanged. A deprecated
  `typealias NoteServiceError = NotesError` keeps old spellings compiling,
  with a rename fix-it.
- **Runner failures are wrapped.** A `NoteService` call that used to throw
  a bare `AppleScriptError` now throws `NotesError.appleScript(_)`:

  ```swift
  // 2.x
  } catch let error as AppleScriptError { … }
  } catch let error as NoteServiceError { … }

  // 3.0: `error` is already a NotesError; no casts
  } catch {
      switch error {
      case let .appleScript(scriptError): …        // .runtime / .compile
      case let .invalidInput(what): …
      case let .scriptFailure(why): …
      }
  }
  ```

  Pattern clauses such as `catch .appleScript(let e)` work too. Swift
  doesn't treat a chain of them as exhaustive, though, so end the chain
  with a plain `catch` or use the `switch` above.

  A 2.x `catch let e as AppleScriptError` around a `NoteService` call no
  longer matches anything; the compiler warns that the cast always fails.
  `#expect(throws: AppleScriptError.self)` in tests compiles but now
  fails at runtime, so expect `NotesError.appleScript(.runtime("…"))`
  instead.
- **Custom runners must throw `AppleScriptError`.** Change
  `func run(source:) async throws -> String` to
  `async throws(AppleScriptError) -> String`, and map your own failures
  onto `.runtime` / `.compile`. A runner that never fails can drop
  `throws`.
- `errorDescription` is unchanged for every failure. `.appleScript`
  forwards the wrapped `AppleScriptError`'s text.
- `NoteStoreReader` is untouched; it still throws `NoteStoreReaderError`.

## License

MIT. See [LICENSE](LICENSE).
