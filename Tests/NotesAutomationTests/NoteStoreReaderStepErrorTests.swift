import Foundation
import SQLite3
import Testing
@testable import NotesAutomation

/// A query can prepare cleanly and still fail while stepping (SQLITE_BUSY
/// under a Notes.app write, SQLITE_CORRUPT, SQLITE_IOERR, …). The reader
/// must surface that as an error, never as a short or empty result.
@Suite("NoteStoreReader step errors")
struct NoteStoreReaderStepErrorTests {

    /// Replaces `ZICCLOUDSYNCINGOBJECT` with a view whose `ZTITLE1` /
    /// `ZTITLE2` column raises a runtime error (`abs(INT64_MIN)` →
    /// "integer overflow") for one row. `sqlite3_prepare_v2` succeeds;
    /// only `sqlite3_step` fails.
    private func makeStepFailingFixture() throws -> String {
        let path = try NoteStoreFixture.create()
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw NoteStoreFixture.FixtureError.openFailed(path)
        }
        defer { sqlite3_close_v2(db) }
        let sql = """
            ALTER TABLE ZICCLOUDSYNCINGOBJECT RENAME TO RAW_OBJECTS;
            CREATE VIEW ZICCLOUDSYNCINGOBJECT AS
            SELECT Z_PK, Z_ENT, ZIDENTIFIER,
                   CASE WHEN Z_PK = 2 THEN abs(-9223372036854775808) ELSE ZTITLE1 END AS ZTITLE1,
                   CASE WHEN Z_PK = 101 THEN abs(-9223372036854775808) ELSE ZTITLE2 END AS ZTITLE2,
                   ZSNIPPET, ZFOLDER, ZFOLDERTYPE, ZMARKEDFORDELETION,
                   ZMODIFICATIONDATE1, ZCREATIONDATE1
            FROM RAW_OBJECTS;
            """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NoteStoreFixture.FixtureError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
        return path
    }

    @Test("list throws sqliteError when a step fails instead of returning partial results")
    func listThrowsOnStepError() async throws {
        let path = try makeStepFailingFixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)
        await #expect(throws: NoteStoreReaderError.self) {
            _ = try await reader.list(limit: 20)
        }
    }

    @Test("search throws sqliteError when a step fails")
    func searchThrowsOnStepError() async throws {
        let path = try makeStepFailingFixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)
        await #expect(throws: NoteStoreReaderError.self) {
            _ = try await reader.search(query: "e")
        }
    }

    @Test("folders throws sqliteError when a step fails")
    func foldersThrowsOnStepError() async throws {
        let path = try makeStepFailingFixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)
        await #expect(throws: NoteStoreReaderError.self) {
            _ = try await reader.folders()
        }
    }
}
