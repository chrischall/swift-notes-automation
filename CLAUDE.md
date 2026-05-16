# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Swift 6 library that exposes Apple Notes.app on macOS via two complementary paths:

- **`NoteService`** — AppleScript-backed (`NSAppleScript`). Handles all writes (create/delete) and read-via-Notes.app. Goes through CloudKit so iCloud sync stays coherent.
- **`NoteStoreReader`** — direct read-only SQLite access to `NoteStore.sqlite`. ~100× faster for list/search. Requires Full Disk Access.

Target: macOS 14+. Zero external dependencies (SQLite is the system `SQLite3` module; no SPM dep needed). Strict concurrency is on (all public types are `Sendable`).

## Commands

```bash
swift build                  # debug build
swift build -c release       # release build (what the Release workflow runs)
swift test                   # pure-Swift tests only — live suites are opt-in
swift test --filter NoteServiceTests.parseNotes        # single test
swift test --filter NSAppleScriptRunnerTests           # whole suite by name
NOTES_AUTOMATION_INTEGRATION=1 swift test              # also run AppleScript live suites
NOTES_SQLITE_INTEGRATION=1 swift test                  # also run NoteStoreReader integration suite
```

- Three test suites are opt-in, gated by env vars:
  - `NoteServiceIntegrationTests` (`NOTES_AUTOMATION_INTEGRATION=1`) — exercises real Notes.app. Requires **Automation** permission for the test binary (System Settings → Privacy & Security → Automation → xctest binary → Notes, granted on first prompt).
  - `NSAppleScriptRunnerTests` (`NOTES_AUTOMATION_INTEGRATION=1`) — exercises the real `NSAppleScript` bridge with trivial scripts (no permission needed). Opt-in because the bridge misbehaves inside xctest bundles on recent macOS — see the AppleScript quirks section below.
  - `NoteStoreReaderIntegrationTests` (`NOTES_SQLITE_INTEGRATION=1`) — exercises the real `NoteStore.sqlite`. Requires **Full Disk Access** for the test binary.
- Without the env var, every test in those suites is skipped via a `.disabled(if:)` trait, so CI stays deterministic and permission-prompt-free.
- Release: push a `vX.Y.Z` tag. `.github/workflows/release.yml` validates it on `macos-15` (release build + `swift test`) and publishes a GitHub Release with auto-generated notes.

## Architecture

Two independent access paths, picked per-call by the consumer based on which tradeoffs fit best.

### AppleScript path (writes + reads)

Two-layer design so Notes-driving code can be unit-tested without a real Notes.app:

- **`AppleScriptRunner` protocol** (`Sources/NotesAutomation/AppleScriptRunner.swift`) — single async `run(source:) -> String` method. Production impl is `NSAppleScriptRunner`; tests use `FakeAppleScriptRunner` which queues string/error responses and records every call.
- **`NoteService`** (`Sources/NotesAutomation/NoteService.swift`) — the public API (`list`, `search`, `create`, `delete`). It *generates* AppleScript source strings and hands them to an injected runner. The service itself is a value type with no mutable state.

This split means `NoteService`'s logic — script generation, output parsing, input validation — is fully testable without AppleScript ever running. Only the `NSAppleScriptRunner` layer touches the system bridge, and it isolates the non-`Sendable` `NSAppleScript` object by compiling + executing inside `Task.detached`.

### SQLite path (reads only)

- **`NoteStoreReader`** (`Sources/NotesAutomation/NoteStoreReader.swift`) — `actor` that holds an `OpaquePointer` to an `sqlite3*` opened via the system `SQLite3` module. No SPM dep. `nonisolated(unsafe)` on the handle because access is serialized through the actor and the nonisolated deinit runs after the last reference is gone.
- Queries the subset of the Notes schema documented in the reader's doc comment: `ZICCLOUDSYNCINGOBJECT` joined against `Z_PRIMARYKEY` (to filter to `ICNote` entities), left-joined to itself for `ZFOLDER → ZTITLE2` folder names. `ZMARKEDFORDELETION` filter + `ZMODIFICATIONDATE1` ordering. Store UUID is read from `Z_METADATA.Z_UUID` once at init to synthesize `x-coredata://…` ids compatible with `NoteService`'s AppleScript-returned ids.
- Tests use `NoteStoreFixture` (test target) to build a throwaway `.sqlite` with the minimum schema subset the reader queries. Update `NoteStoreFixture.schema` if you add new columns to a query — the fixture is deliberately minimal so adding columns gates on a single, obvious place.
- **Schema drift is the biggest risk.** Apple renames columns across macOS releases (the `1` suffix on `ZTITLE1` / `ZMODIFICATIONDATE1` is itself an artifact of a prior rename). If a future macOS breaks the query, fix it under a version check and keep the old column as a fallback — never silently return empty.

### Non-obvious AppleScript quirks to respect

1. **`whose` clauses return specifiers, not references.** Iterating `repeat with n in (notes whose name contains "x")` and then accessing `container of n` fails with `Can't get name of container of item N of every note whose …`. The code works around this by materializing the filter result into a variable first (`set matchedNotes to (every note whose …)`) and indexing (`item i of matchedNotes`) to get a concrete reference. Keep this pattern if you add new list-ish queries — the comment at `NoteService.swift:112` explains it.
2. **Any string interpolated into AppleScript source must have `"` escaped.** `NoteService` does this inline (the local `esc` closure in `create`, the `replacingOccurrences` call in `listOrSearchScript`). If you add another script generator, do the same — there's no central escaping helper.
3. **Create wraps the body as HTML-ish** with the title as `<h1>`. Notes.app treats body as HTML; plaintext in means plaintext out when read back via `plaintext of note`.
4. **Snippet truncation + tab/newline stripping is done in AppleScript, not Swift.** The generated script's `oneLine` handler shells out to `tr` so the Swift-side parser can rely on a clean `id\ttitle\tfolder\tsnippet\n` line format. `parseNoteLines` silently skips lines with fewer than 4 fields — AppleScript can emit a blank row if a single note fails to read (e.g. locked note).
5. **`NSAppleScript` is non-reentrant inside xctest bundles on recent macOS.** Parallel test invocations from the same process flake with error `-1751` ("event not handled") even for trivial scripts like `return "hello"`. Any new test suite that invokes `NSAppleScriptRunner` must carry the `.serialized` trait, and should also gate on `NOTES_AUTOMATION_INTEGRATION=1` so CI doesn't see the flakiness. Production consumers of the library don't hit this — the bridge is reliable from shipped binaries.

### Test-suite conventions

- All real-Notes test folders are named `NotesAutomationTests-<uuid-prefix>` so `cleanUpPriorRuns()` can delete anything left over from a crashed run by prefix-matching. Preserve this prefix convention if you add new integration tests.
- Each real-Notes test calls `cleanUpPriorRuns()` first and `deleteFolder(named:)` in a deferred `Task` — don't rely on the deferred cleanup alone, since a crash still leaves state behind.
- `FakeAppleScriptRunner` (in the test target) is the standard fixture for unit-testing code that takes an `AppleScriptRunner`. It records every call and serves queued responses/errors FIFO — use `queue(_:)` / `queueError(_:)` and assert against `calls`.

## Adding functionality

The README lists capabilities deliberately omitted (update, rich HTML, attachments, iCloud state). Notes.app's AppleScript dictionary supports update — the natural extension is to add `update(id:...)` following the same script-generation + fake-runner test pattern used by `delete(id:)`. Anything requiring direct parsing of `NoteStore.sqlite` (Core Data + protobuf body) is out of scope.

When extending the public surface, mirror the existing conventions: `Sendable` on every public type, `LocalizedError` on error enums (so consumers get a usable `errorDescription`), and `Hashable`/`Identifiable` on value types where the conformance is semantically free.

<!-- pr-workflow:v1 -->
## Pull requests & release notes

**Default workflow: branch + PR, even for solo work.** Direct pushes to `main` skip review *and* skip auto-generated release notes — GitHub's `generate_release_notes` (configured in `.github/release.yml`) only picks up merged PRs. Push directly to `main` only when the user explicitly asks for it (e.g. emergency hotfix).

For every PR, apply exactly one label so it lands in the right release-notes section:

| Label                | Section in release notes |
|----------------------|--------------------------|
| `enhancement`        | Features                 |
| `bug`                | Bug Fixes                |
| `security`           | Security                 |
| `refactor`           | Refactor                 |
| `documentation`      | Documentation            |
| `test`               | Tests                    |
| `dependencies`       | Dependencies             |
| `ci` / `github_actions` | CI & Build            |
| *(none / unmatched)* | Other Changes            |
| `ignore-for-release` | Hidden from notes        |

The **PR title** becomes the bullet — write it like a user-facing changelog entry, not internal shorthand. Conventional-commit prefixes are still fine in commit messages, but the PR title should read clean.

Open with `gh pr create --label <label>` (or `--label ignore-for-release` for chores not worth a line), then **immediately** run `gh pr merge <num> --auto --merge` so the PR merges as soon as CI passes. The repo allows merge commits only (no squash, no rebase) — don't pass `--squash`/`--rebase` or the call will fail.
