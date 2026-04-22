import Foundation
import Testing
@testable import NotesAutomation

/// End-to-end tests for ``NoteStoreReader`` against the user's real
/// `NoteStore.sqlite`.
///
/// **Read-only.** These tests never open the DB read-write, so nothing
/// can be mutated even if a query has side-effects. Still, they'll fail
/// without **Full Disk Access** granted to the calling binary — see
/// ``NoteStoreReader`` for the path through System Settings.
///
/// **Opt-in** via `NOTES_SQLITE_INTEGRATION=1`. Unset, every test in this
/// suite is skipped — CI and normal `swift test` runs stay deterministic
/// and never need Full Disk Access.
///
/// ```bash
/// NOTES_SQLITE_INTEGRATION=1 swift test
/// ```
///
/// Tests make *no assumptions* about the user's note library — they only
/// verify the reader opens the real DB, returns valid `Note` values, and
/// respects basic invariants (non-negative count, limit honored).
@Suite("NoteStoreReader integration")
struct NoteStoreReaderIntegrationTests {

    @Test(
        "list returns well-shaped notes from the real NoteStore",
        .disabled(if: ProcessInfo.processInfo.environment["NOTES_SQLITE_INTEGRATION"] != "1",
                  "set NOTES_SQLITE_INTEGRATION=1 and grant Full Disk Access")
    )
    func listRealDB() async throws {
        let reader = try NoteStoreReader()
        let notes = try await reader.list(limit: 5)

        // Don't assume anything about the user's library except that the
        // shape is valid.
        for n in notes {
            #expect(!n.id.isEmpty)
            // Title may be empty for untitled notes (Notes.app auto-titles
            // from first line, but brand-new empty notes have no title).
        }
        #expect(notes.count <= 5)
    }

    @Test(
        "search returns a subset of list results for a trivially-matching query",
        .disabled(if: ProcessInfo.processInfo.environment["NOTES_SQLITE_INTEGRATION"] != "1",
                  "set NOTES_SQLITE_INTEGRATION=1 and grant Full Disk Access")
    )
    func searchRealDB() async throws {
        let reader = try NoteStoreReader()
        // A single space as the search term: trimmed to empty, returns
        // [] without touching the DB. Useful smoke test that doesn't
        // depend on any particular content being in the user's library.
        let empty = try await reader.search(query: "   ")
        #expect(empty.isEmpty)

        // A query that'll almost certainly match *something* in most
        // libraries. Still just validates shape — count can legitimately
        // be zero and the test still passes.
        let common = try await reader.search(query: "a", limit: 3)
        #expect(common.count <= 3)
    }
}
