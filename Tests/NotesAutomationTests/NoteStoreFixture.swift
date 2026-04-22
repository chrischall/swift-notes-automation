import Foundation
import SQLite3
@testable import NotesAutomation

/// Builds a throwaway SQLite file that matches the subset of the Notes.app
/// schema that ``NoteStoreReader`` queries. Purpose:
///
/// 1. Prove the query shape in `NoteStoreReader.baseQuery` works against
///    an Apple-Notes-style schema (joins on `Z_PRIMARYKEY`, soft-delete
///    filter, folder left-join).
/// 2. Exercise the reader without requiring Full Disk Access or a real
///    Notes library on the test machine.
///
/// Seeds are tiny (a few notes across two folders + one soft-deleted
/// note + one orphan without a folder) so tests stay deterministic.
///
/// The schema here is *not* complete — it's the minimum surface the
/// reader touches. Adding columns is fine; removing columns will break
/// the reader's query and fail its tests, which is the correct signal.
enum NoteStoreFixture {
    /// Column types and names were captured from the real macOS 14 Notes
    /// schema. Only the columns the reader queries are included; real
    /// Notes has ~100 more columns we don't care about here.
    static let schema = """
        CREATE TABLE Z_PRIMARYKEY (
            Z_ENT INTEGER PRIMARY KEY,
            Z_NAME VARCHAR,
            Z_SUPER INTEGER,
            Z_MAX INTEGER
        );
        CREATE TABLE Z_METADATA (
            Z_VERSION INTEGER PRIMARY KEY,
            Z_UUID VARCHAR,
            Z_PLIST BLOB
        );
        CREATE TABLE ZICCLOUDSYNCINGOBJECT (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            ZIDENTIFIER VARCHAR,
            ZTITLE1 VARCHAR,
            ZTITLE2 VARCHAR,
            ZSNIPPET VARCHAR,
            ZFOLDER INTEGER,
            ZMARKEDFORDELETION INTEGER,
            ZMODIFICATIONDATE1 REAL,
            ZCREATIONDATE1 REAL
        );
        """

    struct SeedNote {
        let pk: Int
        let identifier: String
        let title: String
        let snippet: String
        let folderPK: Int?
        let markedForDeletion: Bool
        /// Seconds since Apple's Core Data reference date (2001-01-01 UTC).
        /// Tests use this as a sort key — higher = more recent.
        let modificationDate: Double
    }

    struct SeedFolder {
        let pk: Int
        let title: String
    }

    /// Writes a tmp .sqlite file with schema + seeds. Deleting the file
    /// after the test is the caller's responsibility (usually via
    /// `defer { try? FileManager.default.removeItem(atPath: path) }`).
    static func create(
        folders: [SeedFolder] = defaultFolders,
        notes: [SeedNote] = defaultNotes,
        storeUUID: String? = "FIXTURE-UUID-0001"
    ) throws -> String {
        let path = NSTemporaryDirectory() +
            "notes-fixture-\(UUID().uuidString).sqlite"

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw FixtureError.openFailed(path)
        }
        defer { sqlite3_close_v2(db) }

        try exec(db, schema)

        // Z_PRIMARYKEY rows — 1=ICNote, 2=ICFolder.
        try exec(db, "INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (1, 'ICNote'), (2, 'ICFolder');")

        if let storeUUID {
            try exec(db, "INSERT INTO Z_METADATA (Z_VERSION, Z_UUID) VALUES (1, '\(storeUUID)');")
        }

        for f in folders {
            let sql = """
                INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZTITLE2) VALUES (\(f.pk), 2, '\(escape(f.title))');
                """
            try exec(db, sql)
        }

        for n in notes {
            let folder = n.folderPK.map(String.init) ?? "NULL"
            let deleted = n.markedForDeletion ? 1 : 0
            let sql = """
                INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZSNIPPET, ZFOLDER,
                 ZMARKEDFORDELETION, ZMODIFICATIONDATE1)
                VALUES (\(n.pk), 1, '\(escape(n.identifier))',
                        '\(escape(n.title))', '\(escape(n.snippet))',
                        \(folder), \(deleted), \(n.modificationDate));
                """
            try exec(db, sql)
        }

        return path
    }

    // MARK: - Defaults

    static let defaultFolders: [SeedFolder] = [
        .init(pk: 100, title: "Notes"),
        .init(pk: 101, title: "Work"),
    ]

    static let defaultNotes: [SeedNote] = [
        .init(pk: 1, identifier: "UUID-A", title: "Shopping list",
              snippet: "Milk, eggs, bread", folderPK: 100,
              markedForDeletion: false, modificationDate: 1000),
        .init(pk: 2, identifier: "UUID-B", title: "Meeting notes",
              snippet: "Q2 plan review", folderPK: 101,
              markedForDeletion: false, modificationDate: 2000),
        .init(pk: 3, identifier: "UUID-C", title: "Old idea",
              snippet: "Was going to build a thing", folderPK: 100,
              markedForDeletion: true, modificationDate: 500),
        .init(pk: 4, identifier: "UUID-D", title: "Orphan",
              snippet: "Note with no folder", folderPK: nil,
              markedForDeletion: false, modificationDate: 1500),
        .init(pk: 5, identifier: "UUID-E", title: "Cookies",
              snippet: "Recipe for chocolate cookies",
              folderPK: 100, markedForDeletion: false,
              modificationDate: 3000),
    ]

    // MARK: - Internals

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "rc=\(rc)"
            sqlite3_free(err)
            throw FixtureError.execFailed(msg)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    enum FixtureError: Error {
        case openFailed(String)
        case execFailed(String)
    }
}
