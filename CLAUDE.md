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
- Release is **release-please**-driven, not tag-driven: merging Conventional-Commit PRs to `main` makes `.github/workflows/release-please.yml` open/update a release PR; merging that PR cuts the `vX.Y.Z` tag + GitHub Release. See *Pull requests & release notes* below. CI (`.github/workflows/ci.yml`, `macos-15`) runs `swift build` + `swift test` as the final merge gate.

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

1. **`whose` clauses return specifiers, not references.** Iterating `repeat with n in (notes whose name contains "x")` and then accessing `container of n` fails with `Can't get name of container of item N of every note whose …`. The code works around this by materializing the filter result into a variable first (`set matchedNotes to (every note whose …)`) and indexing (`item i of matchedNotes`) to get a concrete reference. Keep this pattern if you add new list-ish queries — see the `> Note:` doc-comment block on `listOrSearchScript` in `Sources/NotesAutomation/NoteService.swift`.
2. **Any string interpolated into AppleScript source must go through `escapeForAppleScript`.** `NoteService` has a central helper, `static func escapeForAppleScript(_ value: String) -> String` (`Sources/NotesAutomation/NoteService.swift`), used by every script generator (`create`, `deleteScript`, `listOrSearchScript`). It doubles backslashes **first**, then backslash-escapes double-quotes — order matters, since escaping quotes alone (or in the wrong order) leaves input like `\"` or a trailing `\` able to terminate the string literal early and inject AppleScript that reaches `do shell script`. If you add another script generator, route interpolated values through this helper rather than escaping inline.
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

<!-- pr-workflow:v2 -->
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

The **PR title MUST be a Conventional Commit**, written user-facing (`fix(scope): …`, `feat(scope): …`), not internal shorthand. Because the repo squash-merges, the PR title *becomes the squash commit's subject line* — the only thing release-please parses to pick the version bump and changelog section. Only `feat` (minor), `fix` (patch), and `!`/`BREAKING CHANGE` (major) cut a release; `perf`/`refactor`/`docs` show in the changelog without bumping; `ci`/`test`/`build`/`chore` are recognised but hidden (see `release-please-config.json` → `changelog-sections`). A title without a conventional type is invisible to release-please — no bump, no changelog line. Prefixes in *individual commits* don't help; squash keeps only the title.

Open with `gh pr create --label <label>` (or `--label ignore-for-release` for chores not worth a line). **Don't run `gh pr merge` yourself** — the `chrischall/workflows` pipeline does it: `pr-auto-review.yml` reviews every non-release PR, and on a `pass` or `warn` verdict it arms `ready-to-merge`; `auto-merge.yml` then squash-merges the moment CI is green. A `fail` verdict blocks until the findings are addressed. The repo is **squash-only** (no merge commit, no rebase), so don't pass `--merge`/`--rebase`. The release-please PR is skipped by auto-review — ship it by adding `release-ready` yourself.

### Auto-review follow-up issues

When a PR's auto-review verdict is `warn` or `fail`, the `chrischall/workflows` pipeline opens or updates a single `auto-review-followup` issue ("Auto-review follow-ups for PR #N") whose checklist captures every finding, and links it from the PR's `<!-- auto-review-verdict -->` comment (`📋 Tracking follow-ups: #N`). `warn` (nits only) still auto-merges — the issue carries the nits forward, so most nits are fixed in a *later* PR; `fail` blocks until the important findings are addressed on the PR itself.

When asked to address the auto-review comments / review findings on a PR:

1. Read the verdict comment, open the linked `auto-review-followup` issue, and treat its checklist as the work list (alongside any inline review comments).
2. Resolve each item, checking off only what you've **verified** is genuinely fixed.
3. If every item is resolved on the current PR, add `Closes #<issue>` to that PR's body so the merge closes it; if some are deferred, check off only the resolved ones and leave the issue open.
4. For nits whose `warn` PR already auto-merged, address them in a follow-up PR that references `Closes #<issue>`.

(Mirrors the fleet-wide convention in `~/.claude/CLAUDE.md`.)
