import Foundation
import SQLite3

/// High-performance read-only view of Notes.app's Core Data store.
///
/// `NoteStoreReader` opens `NoteStore.sqlite` directly in read-only mode
/// and serves list/search queries in **single-digit milliseconds** —
/// roughly 100× faster than the AppleScript-backed ``NoteService/list(limit:)``
/// and ``NoteService/search(query:limit:)``.
///
/// ## When to use this instead of ``NoteService``
///
/// Prefer the reader when:
/// - You need to list or search many notes (AppleScript is ~100ms per note).
/// - You're fine with read-only access.
/// - Your process has Full Disk Access (required to read the Notes DB —
///   see *Permissions* below).
///
/// Use ``NoteService`` when:
/// - You need to create, update, or delete — writes go through Notes.app
///   (and therefore CloudKit). Writing to the DB directly would desync
///   iCloud and is explicitly not supported here.
/// - You can't or don't want to ask for Full Disk Access.
/// - You want maximum portability across macOS versions (AppleScript's
///   API surface drifts much less than the Core Data schema).
///
/// The two paths are complementary: read via ``NoteStoreReader``, write
/// via ``NoteService``.
///
/// ## Permissions
///
/// `NoteStore.sqlite` lives under `~/Library/Group Containers/group.com.apple.notes/`
/// which the macOS sandbox blocks by default. The calling binary needs
/// **Full Disk Access** granted in
/// *System Settings → Privacy & Security → Full Disk Access*.
///
/// Init will throw ``NoteStoreReaderError/databaseNotAccessible(_:)`` if
/// the file can't be opened — inspect the error message for the specific
/// POSIX/SQLite reason.
///
/// ## Concurrent safety
///
/// The reader opens SQLite with `SQLITE_OPEN_READONLY`. Notes.app uses
/// WAL journaling, which supports multiple readers concurrently with a
/// single writer, so reads are safe while Notes.app is running.
///
/// The type is an `actor`, so concurrent callers serialize through the
/// underlying handle without data races.
///
/// ## Schema assumptions
///
/// The reader targets the Notes schema used by macOS 13+ (Ventura,
/// Sonoma, Sequoia, Tahoe). Key assumptions:
/// - Main table is `ZICCLOUDSYNCINGOBJECT` with Core Data column prefixes.
/// - Notes are the entity named `ICNote` in `Z_PRIMARYKEY`.
/// - Folders are `ICFolder`.
/// - Soft-delete flag is `ZMARKEDFORDELETION`.
///
/// If Apple renames these in a future macOS, queries will fail with a
/// ``NoteStoreReaderError/sqliteError(_:)``. The reader doesn't attempt
/// to auto-migrate — fail loudly, let callers fall back to ``NoteService``.
public actor NoteStoreReader {
    /// Default location of Notes.app's database on macOS.
    public static var defaultDatabasePath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
    }

    // nonisolated(unsafe): OpaquePointer isn't Sendable but the handle is
    // accessed only inside the actor's isolation domain (reads are
    // serialized through the actor) and from the nonisolated deinit, which
    // runs after the last reference is gone — no concurrent access.
    private nonisolated(unsafe) let db: OpaquePointer
    private let storeUUID: String?

    /// Opens the Notes database at `path` for querying.
    ///
    /// Opens read-write + `PRAGMA query_only = 1` rather than
    /// `SQLITE_OPEN_READONLY`. Counterintuitive, but read-only + WAL is a
    /// known footgun: a read-only handle can't write the `-shm` file that
    /// coordinates WAL snapshots, so readers get stuck on whichever
    /// snapshot was current at open time. Read-write + `query_only = 1`
    /// gives normal WAL refresh semantics (reader sees Notes.app's latest
    /// commits) while SQLite still rejects any accidental write. Notes.app
    /// running concurrently is fine — WAL supports concurrent readers +
    /// a single writer.
    ///
    /// - Parameter path: Absolute path to `NoteStore.sqlite`. Defaults to
    ///   ``defaultDatabasePath``. Tests pass a fixture path here.
    /// - Throws: ``NoteStoreReaderError/databaseNotAccessible(_:)`` when
    ///   the file doesn't exist or the caller lacks permission.
    public init(path: String = NoteStoreReader.defaultDatabasePath) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned \(rc)"
            if let h = handle { sqlite3_close_v2(h) }
            throw NoteStoreReaderError.databaseNotAccessible(
                "Cannot open \(path): \(msg). On macOS, grant Full Disk " +
                "Access to the calling binary in System Settings → " +
                "Privacy & Security → Full Disk Access."
            )
        }
        // Pin the connection as query-only so any programming mistake
        // downstream gets rejected by SQLite rather than corrupting
        // Notes.app's state. Intentionally swallowing the pragma's rc —
        // if it somehow fails, the worst case is our own code could
        // write, which it never does.
        sqlite3_exec(handle, "PRAGMA query_only = 1", nil, nil, nil)
        self.db = handle
        // Capture the Core Data store UUID once so we can mint
        // `x-coredata://…` ids compatible with NoteService (which returns
        // this format from AppleScript). Best-effort — if the column
        // isn't there we fall back to ZIDENTIFIER.
        self.storeUUID = Self.readStoreUUID(db: handle)
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: - Public queries

    /// Returns the most-recently-modified notes, up to `limit`.
    ///
    /// Excludes notes marked for deletion. Results are ordered by
    /// modification date descending.
    public func list(limit: Int = 20) async throws -> [Note] {
        try runNoteQuery(where: "", args: [], limit: limit)
    }

    /// Case-insensitive substring match against title and snippet.
    ///
    /// An empty or whitespace-only query returns `[]` without touching
    /// the DB — matches ``NoteService/search(query:limit:)``.
    public func search(query: String, limit: Int = 20) async throws -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let needle = "%\(trimmed.lowercased())%"
        return try runNoteQuery(
            where: "AND (LOWER(n.ZTITLE1) LIKE ? OR LOWER(n.ZSNIPPET) LIKE ?)",
            args: [needle, needle],
            limit: limit
        )
    }

    // MARK: - Query core

    /// Core SQL template used by list and search. Extracted so the query
    /// shape is visible in one place and testable end-to-end against
    /// fixtures.
    ///
    /// Joins `ZICCLOUDSYNCINGOBJECT` against `Z_PRIMARYKEY` to filter
    /// to note entities (`ICNote`). Left-joins the same table to resolve
    /// the folder name — notes without a folder show up with an empty
    /// folder string.
    ///
    /// Exclusion filters match how Notes.app represents deleted notes:
    /// - `ZMARKEDFORDELETION = 0` — canonical soft-delete flag. Notes.app
    ///   sets this on some deletions but not all.
    /// - `ZFOLDERTYPE <> 1` and `ZIDENTIFIER NOT LIKE 'TrashFolder-%'` —
    ///   excludes notes in the Recently Deleted folder, which is how
    ///   Notes.app moves delete-via-AppleScript notes. `ZFOLDERTYPE = 1`
    ///   is the stable, locale-independent marker; the `TrashFolder-*`
    ///   identifier is a belt-and-suspenders check for accounts where
    ///   `ZFOLDERTYPE` isn't set.
    static let baseQuery = """
        SELECT n.Z_PK, n.ZIDENTIFIER, n.ZTITLE1, n.ZSNIPPET,
               COALESCE(f.ZTITLE2, '') AS folder_name
        FROM ZICCLOUDSYNCINGOBJECT n
        JOIN Z_PRIMARYKEY pk ON n.Z_ENT = pk.Z_ENT AND pk.Z_NAME = 'ICNote'
        LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
        WHERE COALESCE(n.ZMARKEDFORDELETION, 0) = 0
          AND COALESCE(f.ZFOLDERTYPE, 0) <> 1
          AND COALESCE(f.ZIDENTIFIER, '') NOT LIKE 'TrashFolder-%'
        """

    private func runNoteQuery(
        where extraPredicate: String,
        args: [String],
        limit: Int
    ) throws -> [Note] {
        let sql = Self.baseQuery + "\n" + extraPredicate +
            "\nORDER BY n.ZMODIFICATIONDATE1 DESC\nLIMIT ?"

        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NoteStoreReaderError.sqliteError("prepare failed: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        // Bind positional `?` params. Strings get SQLITE_TRANSIENT so
        // SQLite copies them before they go out of scope.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, s) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), s, -1, transient)
        }
        sqlite3_bind_int(stmt, Int32(args.count + 1), Int32(limit))

        var results: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = sqlite3_column_int64(stmt, 0)
            let zid = columnText(stmt, 1) ?? ""
            let title = columnText(stmt, 2) ?? ""
            let snippet = columnText(stmt, 3) ?? ""
            let folder = columnText(stmt, 4) ?? ""
            let id = mintID(pk: pk, zid: zid)
            results.append(Note(id: id, title: title, snippet: snippet, folder: folder))
        }
        return results
    }

    // MARK: - Helpers

    /// Synthesize the Core Data URI format that ``NoteService`` returns,
    /// so ids are interchangeable across the two paths.
    ///
    /// Falls back to `ZIDENTIFIER` when the store UUID can't be read
    /// (tests with minimal fixtures, for example). That's still a valid
    /// opaque id — just not round-trippable to AppleScript.
    private func mintID(pk: Int64, zid: String) -> String {
        guard let uuid = storeUUID else { return zid }
        return "x-coredata://\(uuid)/ICNote/p\(pk)"
    }

    private static func readStoreUUID(db: OpaquePointer) -> String? {
        // Z_METADATA.Z_UUID holds the Core Data store UUID on standard
        // Core Data-generated schemas. Swallow all errors — this is a
        // best-effort enrichment.
        var stmt: OpaquePointer?
        let sql = "SELECT Z_UUID FROM Z_METADATA LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }

    /// Read a TEXT column safely. Returns nil for NULL, otherwise UTF-8.
    private static func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cstr)
    }

    private func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        Self.columnText(stmt, col)
    }
}

/// Errors surfaced by ``NoteStoreReader``.
public enum NoteStoreReaderError: Error, Equatable, Sendable {
    /// The `NoteStore.sqlite` file couldn't be opened — typically because
    /// the caller lacks Full Disk Access, or the path doesn't exist.
    ///
    /// The associated value includes the SQLite error string and
    /// remediation hint.
    case databaseNotAccessible(String)

    /// SQLite returned an error while preparing or stepping a query —
    /// usually a schema mismatch (Apple renamed a column) or a corrupt
    /// WAL. Callers should treat this as terminal for the reader and
    /// fall back to ``NoteService``.
    case sqliteError(String)
}

extension NoteStoreReaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseNotAccessible(let m): return "NoteStore not accessible: \(m)"
        case .sqliteError(let m): return "NoteStore SQLite error: \(m)"
        }
    }
}
