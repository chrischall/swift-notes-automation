import Foundation
import SQLite3
import Testing
@testable import NotesAutomation

/// The reader must never write to Notes.app's store — not even through
/// SQLite's own WAL maintenance. When the reader's handle is the *last*
/// connection on a WAL-mode database (Notes.app not running), a writable
/// handle checkpoints the WAL into the main file on close. `PRAGMA query_only` blocks SQL writes but not that.
@Suite("NoteStoreReader WAL safety")
struct NoteStoreReaderWALTests {

    /// Builds a WAL-mode fixture whose latest commit lives only in the
    /// `-wal` file (no `-shm`), as Notes.app leaves the store when it
    /// quits without a final checkpoint. Returns the directory and the
    /// db path inside it.
    private func walOnlyFixture() throws -> (dir: String, db: String) {
        let src = try NoteStoreFixture.create()
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: src + suffix)
            }
        }

        var writer: OpaquePointer?
        guard sqlite3_open(src, &writer) == SQLITE_OK, let writer else {
            Issue.record("could not open fixture for writing")
            throw CancellationError()
        }
        #expect(sqlite3_exec(writer, "PRAGMA journal_mode = WAL", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(writer, "PRAGMA wal_autocheckpoint = 0", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(
            writer,
            "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE1 = 'Cookies (from WAL)' WHERE Z_PK = 5",
            nil, nil, nil) == SQLITE_OK)

        // Snapshot db + wal while the writer still holds them open, so
        // the copy has an un-checkpointed WAL and no -shm.
        let dir = NSTemporaryDirectory() + "notes-wal-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let db = dir + "/NoteStore.sqlite"
        try FileManager.default.copyItem(atPath: src, toPath: db)
        try FileManager.default.copyItem(atPath: src + "-wal", toPath: db + "-wal")
        sqlite3_close_v2(writer)
        return (dir, db)
    }

    @Test("closing the reader's handle never checkpoints the WAL into the store or deletes it")
    func readerLeavesWALAlone() async throws {
        let (dir, db) = try walOnlyFixture()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let before = try Data(contentsOf: URL(fileURLWithPath: db))

        let reader = try NoteStoreReader(path: db)
        let titles = try await reader.list(limit: 20).map(\.title)
        // The reader still sees the WAL-only commit…
        #expect(titles.contains("Cookies (from WAL)"))

        // …but leaves the main file byte-identical and the WAL in place.
        let after = try Data(contentsOf: URL(fileURLWithPath: db))
        #expect(after == before)
        #expect(FileManager.default.fileExists(atPath: db + "-wal"))
    }

    @Test("a WAL store with no -wal file (Notes.app shut down cleanly) still opens without modifying the store")
    func cleanlyClosedWALStore() async throws {
        let path = try NoteStoreFixture.create()
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }
        var writer: OpaquePointer?
        guard sqlite3_open(path, &writer) == SQLITE_OK, let writer else {
            Issue.record("could not open fixture for writing")
            return
        }
        #expect(sqlite3_exec(writer, "PRAGMA journal_mode = WAL", nil, nil, nil) == SQLITE_OK)
        sqlite3_close_v2(writer)
        #expect(!FileManager.default.fileExists(atPath: path + "-wal"))

        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let reader = try NoteStoreReader(path: path)
        #expect(try await reader.list(limit: 20).map(\.title).contains("Cookies"))
        #expect(try await reader.list(limit: 20).map(\.title).contains("Cookies"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    }

    @Test("a read-only reader still sees commits a concurrent WAL writer makes after init")
    func readerSeesLaterCommits() async throws {
        let path = try NoteStoreFixture.create()
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }
        var writer: OpaquePointer?
        guard sqlite3_open(path, &writer) == SQLITE_OK, let writer else {
            Issue.record("could not open fixture for writing")
            return
        }
        defer { sqlite3_close_v2(writer) }
        #expect(sqlite3_exec(writer, "PRAGMA journal_mode = WAL", nil, nil, nil) == SQLITE_OK)

        let reader = try NoteStoreReader(path: path)
        #expect(try await reader.list(limit: 20).map(\.title).contains("Cookies"))

        // Stands in for Notes.app committing while the reader is alive.
        #expect(sqlite3_exec(
            writer,
            "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE1 = 'Cookies v2' WHERE Z_PK = 5",
            nil, nil, nil) == SQLITE_OK)

        let titles = try await reader.list(limit: 20).map(\.title)
        #expect(titles.contains("Cookies v2"))
        #expect(!titles.contains("Cookies"))
    }
}
