import Foundation
import Testing
@testable import NotesAutomation

@Suite("NoteStoreReader")
struct NoteStoreReaderTests {

    // MARK: - setup helper

    /// Builds a fresh fixture DB and hands the caller both the reader
    /// and a cleanup closure. Using a `defer` inside each test keeps
    /// the file lifecycle visible in-place.
    private func withFixture(
        folders: [NoteStoreFixture.SeedFolder] = NoteStoreFixture.defaultFolders,
        notes: [NoteStoreFixture.SeedNote] = NoteStoreFixture.defaultNotes,
        storeUUID: String? = "FIXTURE-UUID-0001",
        _ body: (NoteStoreReader) async throws -> Void
    ) async throws {
        let path = try NoteStoreFixture.create(
            folders: folders, notes: notes, storeUUID: storeUUID)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)
        try await body(reader)
    }

    // MARK: - open / init

    @Test("init throws databaseNotAccessible for a non-existent path")
    func initMissingPath() async throws {
        #expect(throws: NoteStoreReaderError.self) {
            _ = try NoteStoreReader(path: "/nonexistent/notes.sqlite")
        }
    }

    // MARK: - list

    @Test("list returns notes ordered by modification date desc, excluding deleted")
    func listOrderAndFilter() async throws {
        try await withFixture { reader in
            let notes = try await reader.list(limit: 20)
            let titles = notes.map(\.title)
            // Soft-deleted "Old idea" is excluded.
            // Order by mod-date desc: Cookies(3000), Meeting(2000),
            // Orphan(1500), Shopping(1000).
            #expect(titles == ["Cookies", "Meeting notes", "Orphan", "Shopping list"])
        }
    }

    @Test("list respects the limit parameter")
    func listLimit() async throws {
        try await withFixture { reader in
            let notes = try await reader.list(limit: 2)
            #expect(notes.count == 2)
            #expect(notes[0].title == "Cookies")
        }
    }

    @Test("list resolves folder names via left-join")
    func listFolderNames() async throws {
        try await withFixture { reader in
            let notes = try await reader.list(limit: 10)
            let byTitle = Dictionary(uniqueKeysWithValues: notes.map { ($0.title, $0.folder) })
            #expect(byTitle["Cookies"] == "Notes")
            #expect(byTitle["Meeting notes"] == "Work")
            #expect(byTitle["Shopping list"] == "Notes")
            // Orphan note has no folder — empty string, not crash.
            #expect(byTitle["Orphan"] == "")
        }
    }

    @Test("list excludes notes in the Recently Deleted folder (ZFOLDERTYPE=1)")
    func listExcludesTrashByFolderType() async throws {
        try await withFixture { reader in
            let notes = try await reader.list(limit: 20)
            // "Trashed thoughts" (pk 6) is in the fixture's trash folder
            // (ZFOLDERTYPE=1). The user-visible list must not include it,
            // even though its ZMARKEDFORDELETION stays 0 — real Notes.app
            // behavior when deleting via AppleScript.
            #expect(!notes.contains { $0.title == "Trashed thoughts" })
        }
    }

    @Test("list excludes trash by ZIDENTIFIER prefix even if ZFOLDERTYPE is missing")
    func listExcludesTrashByIdentifier() async throws {
        // Belt-and-suspenders: for accounts where Notes doesn't populate
        // ZFOLDERTYPE (older schemas), the TrashFolder-* identifier
        // naming must still catch the folder.
        let folders: [NoteStoreFixture.SeedFolder] = [
            .init(pk: 100, title: "Notes"),
            .init(pk: 102, title: "Trash", folderType: 0,
                  identifier: "TrashFolder-LocalAccount"),
        ]
        let notes: [NoteStoreFixture.SeedNote] = [
            .init(pk: 1, identifier: "UUID-A", title: "Visible",
                  snippet: "", folderPK: 100, markedForDeletion: false,
                  modificationDate: 2000),
            .init(pk: 2, identifier: "UUID-B", title: "Hidden",
                  snippet: "", folderPK: 102, markedForDeletion: false,
                  modificationDate: 1000),
        ]
        try await withFixture(folders: folders, notes: notes) { reader in
            let results = try await reader.list(limit: 10)
            #expect(results.map(\.title) == ["Visible"])
        }
    }

    @Test("search also excludes notes in the trash folder")
    func searchExcludesTrash() async throws {
        try await withFixture { reader in
            // "Trashed thoughts" would match the substring "thoughts",
            // but it's in the trash folder — must not surface.
            let results = try await reader.search(query: "thoughts")
            #expect(results.isEmpty)
        }
    }

    // MARK: - search

    @Test("search matches against title case-insensitively")
    func searchTitle() async throws {
        try await withFixture { reader in
            let hits = try await reader.search(query: "COOKIES")
            #expect(hits.count == 1)
            #expect(hits[0].title == "Cookies")
        }
    }

    @Test("search matches against snippet (body fallback)")
    func searchSnippet() async throws {
        try await withFixture { reader in
            let hits = try await reader.search(query: "chocolate")
            #expect(hits.count == 1)
            #expect(hits[0].title == "Cookies")
        }
    }

    @Test("search honors the same deletion + order rules as list")
    func searchExcludesDeleted() async throws {
        try await withFixture { reader in
            // "Old idea" is marked for deletion and should not appear
            // even when its text matches the query.
            let hits = try await reader.search(query: "idea")
            #expect(hits.isEmpty)
        }
    }

    @Test("search returns [] for empty / whitespace queries")
    func searchEmpty() async throws {
        try await withFixture { reader in
            let empty = try await reader.search(query: "")
            let whitespace = try await reader.search(query: "   ")
            #expect(empty.isEmpty)
            #expect(whitespace.isEmpty)
        }
    }

    @Test("search respects the limit parameter")
    func searchLimit() async throws {
        // Seed multiple notes that all match "recipe" to prove limit works.
        let folders: [NoteStoreFixture.SeedFolder] = [.init(pk: 100, title: "Recipes")]
        let notes: [NoteStoreFixture.SeedNote] = (1...5).map { i in
            .init(pk: i, identifier: "UUID-\(i)",
                  title: "Recipe \(i)", snippet: "cookie recipe \(i)",
                  folderPK: 100, markedForDeletion: false,
                  modificationDate: Double(i) * 100)
        }
        try await withFixture(folders: folders, notes: notes) { reader in
            let hits = try await reader.search(query: "recipe", limit: 3)
            #expect(hits.count == 3)
            // Limit + mod-date desc = top 3 newest.
            #expect(hits.map(\.title) == ["Recipe 5", "Recipe 4", "Recipe 3"])
        }
    }

    // MARK: - id minting

    @Test("id is minted as a Core Data URI when Z_METADATA.Z_UUID is present")
    func idWithStoreUUID() async throws {
        try await withFixture(storeUUID: "ABC123-STORE") { reader in
            let notes = try await reader.list(limit: 1)
            #expect(notes[0].id == "x-coredata://ABC123-STORE/ICNote/p5")
        }
    }

    @Test("id falls back to ZIDENTIFIER when Z_METADATA is absent")
    func idFallback() async throws {
        try await withFixture(storeUUID: nil) { reader in
            let notes = try await reader.list(limit: 1)
            #expect(notes[0].id == "UUID-E") // Cookies = pk 5 = ZIDENTIFIER UUID-E
        }
    }
}
