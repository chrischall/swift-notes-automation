import Foundation

/// Errors surfaced by ``NoteService`` operations.
public enum NoteServiceError: Error, Equatable, Sendable {
    /// AppleScript ran successfully but Notes.app reported a non-success
    /// result, or the returned payload could not be parsed.
    ///
    /// The associated value carries a human-readable diagnostic intended
    /// for logs, not end users.
    case scriptFailure(String)

    /// The caller passed an empty or whitespace-only string for a
    /// required parameter (most commonly `title` on ``NoteService/create(title:body:folder:)``).
    ///
    /// The associated value names the offending parameter.
    case invalidInput(String)
}

extension NoteServiceError: LocalizedError {
    /// Human-readable description suitable for logs and user display.
    public var errorDescription: String? {
        switch self {
        case .scriptFailure(let message):
            return "Notes script failure: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}

/// High-level wrapper around Apple Notes.app.
///
/// `NoteService` is a thin, testable front for Notes. It generates
/// AppleScript source, hands it to an injected ``AppleScriptRunner``, and
/// parses the result into Swift values — so the bulk of the library's
/// logic is exercised by unit tests without requiring a real Notes.app
/// session.
///
/// ## Usage
///
/// ```swift
/// let notes = NoteService(runner: NSAppleScriptRunner())
///
/// let recent = try await notes.list(limit: 10)
/// let hits   = try await notes.search(query: "milk")
/// let full   = try await notes.get(id: recent[0].id)   // untruncated body
/// let id     = try await notes.create(title: "Plan", body: "…", folder: "Work")
/// try await notes.update(id: id, title: "Plan v2")
/// ```
///
/// ## Scope
///
/// The service exposes the subset of Notes.app's AppleScript surface that
/// maps cleanly to a flat list of notes:
/// - Read: ``list(limit:offset:)``, ``search(query:limit:offset:)`` (both
///   return a truncated ``Note/snippet``), ``get(id:)`` (returns the full,
///   untruncated body as ``NoteDetail``), and ``folders()``.
/// - Write: ``create(title:body:folder:)``, ``update(id:title:body:folder:)``,
///   and ``delete(id:)``.
///
/// Folder structure is represented by the `folder` string on each ``Note``
/// plus the flat ``folders()`` list; there is no nested-folder model.
///
/// ## Concurrency
///
/// The type is a `Sendable` value type and performs all Notes.app work on
/// a detached task inside the runner. Construct one instance and share it
/// across concurrent callers.
public struct NoteService: Sendable {
    private let runner: any AppleScriptRunner

    /// Creates a service that routes AppleScript through `runner`.
    ///
    /// - Parameter runner: The AppleScript executor. Pass
    ///   ``NSAppleScriptRunner`` in production and a fake in tests.
    public init(runner: any AppleScriptRunner) {
        self.runner = runner
    }

    /// Maximum length of the ``Note/snippet`` preview returned by
    /// ``list(limit:offset:)`` and ``search(query:limit:offset:)``.
    ///
    /// A preview is meant to be scannable, not complete — use ``get(id:)``
    /// for a note's full, untruncated body. Bumped from the original 200
    /// so previews carry a bit more context without duplicating `get`.
    public static let snippetPreviewMaxLength = 350

    // MARK: - List / search

    /// Returns the most-recently-modified notes, up to `limit`.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of notes to return. Defaults to `20`.
    ///   - offset: Number of leading notes to skip, for paging through a
    ///     large library. Defaults to `0`.
    /// - Returns: Notes in Notes.app's native iteration order, which is
    ///   typically most-recently-modified first. The array is empty when
    ///   the user has no notes.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when Notes.app is not
    ///   running or Automation permission is denied.
    public func list(limit: Int = 20, offset: Int = 0) async throws -> [Note] {
        let source = Self.listOrSearchScript(query: nil, limit: limit, offset: offset)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    /// Searches notes by a case-insensitive substring match against name
    /// or body.
    ///
    /// An empty or whitespace-only `query` returns `[]` immediately
    /// without running any AppleScript — a cheap guard against accidental
    /// full-library scans.
    ///
    /// - Parameters:
    ///   - query: Substring to match against each note's name and body.
    ///   - limit: Maximum number of results. Defaults to `20`.
    ///   - offset: Number of leading matches to skip, for paging. Defaults
    ///     to `0`.
    /// - Returns: Matching notes, up to `limit`.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when Notes.app is not
    ///   running or Automation permission is denied.
    public func search(query: String, limit: Int = 20, offset: Int = 0) async throws -> [Note] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let source = Self.listOrSearchScript(query: query, limit: limit, offset: offset)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    // MARK: - Get (full body)

    /// Field delimiter for ``getScript(id:)`` output.
    ///
    /// ASCII **record separator** (`U+001E`). Unlike list/search — whose
    /// snippets are whitespace-normalized so tabs and newlines can delimit
    /// fields — a full note body contains arbitrary newlines and tabs, so
    /// the delimiter has to be a character that essentially never appears
    /// in user note text.
    public static let detailFieldSeparator = "\u{001E}"

    /// Fetches a single note's **complete, untruncated** body by id.
    ///
    /// Returns both a plain-text rendering (``NoteDetail/plainText``) and
    /// the raw Notes.app HTML (``NoteDetail/html``), along with the title,
    /// folder, and creation/modification dates. This is the counterpart to
    /// ``list(limit:)`` / ``search(query:limit:)``, which return only a
    /// truncated ``Note/snippet`` preview.
    ///
    /// - Parameter id: The note's opaque id, as returned by ``Note/id`` or
    ///   ``create(title:body:folder:)``. Empty or whitespace-only ids throw
    ///   ``NoteServiceError/invalidInput(_:)`` without running any script.
    /// - Returns: The note's full contents.
    /// - Throws:
    ///   - ``NoteServiceError/invalidInput(_:)`` when `id` is empty.
    ///   - ``NoteServiceError/scriptFailure(_:)`` when Notes.app returned
    ///     output that couldn't be parsed (for example, an empty result
    ///     because no note has that id).
    ///   - ``AppleScriptError/runtime(_:)`` when Notes.app is not running
    ///     or Automation permission is denied.
    public func get(id: String) async throws -> NoteDetail {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NoteServiceError.invalidInput("id is required")
        }
        let raw = try await runner.run(source: Self.getScript(id: id))
        guard let detail = Self.parseNoteDetail(raw) else {
            throw NoteServiceError.scriptFailure(
                "could not parse note detail for id \(id) — no note with that id?"
            )
        }
        return detail
    }

    // MARK: - Folders

    /// Lists the names of all Notes.app folders.
    ///
    /// Enables browsing the folder set, rather than only using a folder
    /// name as a list/search filter. Names are returned in Notes.app's
    /// native iteration order; duplicates are possible when two accounts
    /// each have a folder of the same name.
    ///
    /// - Returns: Folder names. Empty when the user has no folders.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when Notes.app is not
    ///   running or Automation permission is denied.
    public func folders() async throws -> [String] {
        let raw = try await runner.run(source: Self.foldersScript())
        return Self.parseFolderLines(raw)
    }

    // MARK: - Create

    /// Creates a new note with the given title and body.
    ///
    /// The body is wrapped in Notes.app's HTML-ish format with the title
    /// as an `<h1>` so the UI shows a proper heading. Backslashes and quotes
    /// in `title`, `body`, and `folder` are escaped (via
    /// ``escapeForAppleScript(_:)``) before they reach AppleScript, so no
    /// input can terminate the string literal early.
    ///
    /// - Parameters:
    ///   - title: Note name. Must be non-empty after trimming whitespace.
    ///   - body: Note body. HTML is allowed; quotes are escaped for you.
    ///   - folder: Optional folder name. If the folder does not exist,
    ///     it is created. When `nil` or empty, the note is created at
    ///     the default account's top level.
    /// - Returns: The newly-created note's opaque id — matches the
    ///   ``Note/id`` of values returned by ``list(limit:)`` and
    ///   ``search(query:limit:)``.
    /// - Throws: ``NoteServiceError/invalidInput(_:)`` when `title` is
    ///   empty or whitespace-only. ``AppleScriptError/runtime(_:)`` when
    ///   Notes.app is not running or Automation permission is denied.
    public func create(title: String, body: String, folder: String? = nil) async throws -> String {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NoteServiceError.invalidInput("title is required")
        }
        // Notes.app treats the body as HTML-ish; combining title + body so
        // the UI renders a proper header. Both title and body are escaped for
        // the AppleScript string literals via ``escapeForAppleScript`` so a
        // backslash or quote can't terminate the literal early (injection).
        let esc = Self.escapeForAppleScript
        let noteBody = "<h1>\(esc(title))</h1>\n\(esc(body))"

        let folderClause: String
        if let folder, !folder.isEmpty {
            let ef = esc(folder)
            folderClause = """
            set targetFolder to missing value
            try
                set targetFolder to first folder whose name is "\(ef)"
            end try
            if targetFolder is missing value then
                set targetFolder to make new folder with properties {name:"\(ef)"}
            end if
            set newNote to make new note at targetFolder with properties {name:"\(esc(title))", body:"\(noteBody)"}
            """
        } else {
            folderClause = """
            set newNote to make new note with properties {name:"\(esc(title))", body:"\(noteBody)"}
            """
        }
        let source = """
        tell application "Notes"
            \(folderClause)
            return (id of newNote as string)
        end tell
        """
        return try await runner.run(source: source)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Update

    /// Edits an existing note's title, body, and/or containing folder.
    ///
    /// Only the non-`nil` fields are changed; passing `nil` leaves that
    /// aspect of the note untouched. At least one of `title`, `body`, or
    /// `folder` must be non-`nil`.
    ///
    /// The body is applied first and the name last, so an explicit `title`
    /// wins over whatever first line a new `body` would otherwise imply.
    /// Moving to a `folder` that doesn't exist creates it, mirroring
    /// ``create(title:body:folder:)``.
    ///
    /// - Parameters:
    ///   - id: The note's opaque id. Empty or whitespace-only ids throw
    ///     ``NoteServiceError/invalidInput(_:)``.
    ///   - title: New title, or `nil` to leave unchanged.
    ///   - body: New body (HTML allowed), or `nil` to leave unchanged.
    ///   - folder: Folder to move the note into (created if absent), or
    ///     `nil` to leave the note where it is.
    /// - Throws:
    ///   - ``NoteServiceError/invalidInput(_:)`` when `id` is empty or when
    ///     all of `title`, `body`, and `folder` are `nil`.
    ///   - ``AppleScriptError/runtime(_:)`` when Notes.app is not running,
    ///     Automation permission is denied, or no note has that id.
    public func update(
        id: String,
        title: String? = nil,
        body: String? = nil,
        folder: String? = nil
    ) async throws {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NoteServiceError.invalidInput("id is required")
        }
        guard title != nil || body != nil || folder != nil else {
            throw NoteServiceError.invalidInput(
                "nothing to update — provide a title, body, and/or folder"
            )
        }
        _ = try await runner.run(
            source: Self.updateScript(id: id, title: title, body: body, folder: folder)
        )
    }

    // MARK: - Delete

    /// Permanently deletes a note by id. The id format matches what
    /// ``list(limit:)``, ``search(query:limit:)``, and ``create(title:body:folder:)``
    /// return (Notes.app's Core Data URI, e.g. `x-coredata://…/ICNote/p42`).
    ///
    /// - Parameter id: The note's opaque id. Empty or whitespace-only ids
    ///   throw ``NoteServiceError/invalidInput(_:)`` without running any
    ///   AppleScript.
    /// - Throws:
    ///   - ``NoteServiceError/invalidInput(_:)`` when `id` is empty.
    ///   - ``AppleScriptError/runtime(_:)`` when Notes.app is not running,
    ///     Automation permission is denied, or no note with that id exists.
    public func delete(id: String) async throws {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NoteServiceError.invalidInput("id is required")
        }
        _ = try await runner.run(source: Self.deleteScript(id: id))
    }

    // MARK: - Script generation

    /// Escapes a string for safe interpolation inside a double-quoted
    /// AppleScript string literal.
    ///
    /// Order matters: backslashes are doubled **first**, then double-quotes
    /// are backslash-escaped. Escaping quotes only (or escaping in the wrong
    /// order) leaves input like `\"` or a trailing `\` able to terminate the
    /// literal early, so the remainder of the value is parsed as AppleScript
    /// — an injection that reaches `do shell script`.
    static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Constructs a delete-by-id AppleScript.
    ///
    /// Looks up the note via `note id "…"`, which references Notes.app's
    /// Core Data URI. If the note doesn't exist, AppleScript raises at
    /// runtime — callers surface that as ``AppleScriptError/runtime(_:)``.
    ///
    /// - Parameter id: The note's opaque id. Backslashes and double-quotes
    ///   are escaped (via ``escapeForAppleScript(_:)``) defensively before
    ///   interpolation.
    /// - Returns: AppleScript source.
    static func deleteScript(id: String) -> String {
        let esc = escapeForAppleScript(id)
        return """
        tell application "Notes"
            delete note id "\(esc)"
        end tell
        """
    }

    /// Constructs a get-full-note-by-id AppleScript.
    ///
    /// Emits seven ``detailFieldSeparator``-delimited fields on a single
    /// logical result: `id`, `title`, `folder`, `creationDate`,
    /// `modificationDate`, `plaintext`, `html`. The two body fields come
    /// last because they can contain newlines and tabs; the record
    /// separator keeps them unambiguous. Dates are emitted as local-time
    /// `yyyy-MM-dd'T'HH:mm:ss` via a zero-padding handler so
    /// ``parseNoteDetail(_:)`` can parse them without depending on the
    /// machine's locale-formatted date output.
    ///
    /// - Parameter id: The note's opaque id. Backslashes and double-quotes
    ///   are escaped (via ``escapeForAppleScript(_:)``) before interpolation.
    /// - Returns: AppleScript source.
    static func getScript(id: String) -> String {
        let esc = escapeForAppleScript(id)
        return """
        tell application "Notes"
            set n to note id "\(esc)"
            set nid to id of n as string
            set nname to name of n
            set nfolder to ""
            try
                set nfolder to name of (container of n)
            end try
            set nplain to plaintext of n
            set nhtml to body of n
            set ncreated to ""
            try
                set ncreated to my isoDate(creation date of n)
            end try
            set nmodified to ""
            try
                set nmodified to my isoDate(modification date of n)
            end try
            set sep to (ASCII character 30)
            return nid & sep & nname & sep & nfolder & sep & ncreated & sep & nmodified & sep & nplain & sep & nhtml
        end tell

        on pad2(n)
            set s to n as string
            if (length of s) < 2 then set s to "0" & s
            return s
        end pad2

        on isoDate(d)
            return (year of d as string) & "-" & pad2((month of d) as integer) & "-" & pad2(day of d) & "T" & pad2(hours of d) & ":" & pad2(minutes of d) & ":" & pad2(seconds of d)
        end isoDate
        """
    }

    /// Constructs an update-note-by-id AppleScript.
    ///
    /// Emits only the clauses needed for the non-`nil` fields. Order is
    /// deliberate: an optional folder move first, then the body, then the
    /// name — so an explicit `title` overrides the first line that a new
    /// `body` would otherwise set as the note's name.
    ///
    /// - Parameters:
    ///   - id: The note's opaque id (escaped before interpolation).
    ///   - title: New name, or `nil` to skip the `set name` clause.
    ///   - body: New body, or `nil` to skip the `set body` clause.
    ///   - folder: Destination folder (created if absent), or `nil` to
    ///     skip the move.
    /// - Returns: AppleScript source.
    static func updateScript(id: String, title: String?, body: String?, folder: String?) -> String {
        let esc = escapeForAppleScript
        var clauses = ""
        if let folder, !folder.isEmpty {
            let ef = esc(folder)
            clauses += """

                set targetFolder to missing value
                try
                    set targetFolder to first folder whose name is "\(ef)"
                end try
                if targetFolder is missing value then
                    set targetFolder to make new folder with properties {name:"\(ef)"}
                end if
                move n to targetFolder
            """
        }
        if let body {
            clauses += "\n    set body of n to \"\(esc(body))\""
        }
        if let title {
            clauses += "\n    set name of n to \"\(esc(title))\""
        }
        return """
        tell application "Notes"
            set n to note id "\(esc(id))"
        \(clauses)
        end tell
        """
    }

    /// Constructs a list-all-folders AppleScript.
    ///
    /// Emits one folder name per line. Iterates by index (rather than
    /// `name of every folder`, which NSAppleScript would coerce to an
    /// opaque list descriptor) so the runner's string coercion yields a
    /// clean newline-delimited payload.
    ///
    /// - Returns: AppleScript source.
    static func foldersScript() -> String {
        """
        tell application "Notes"
            set out to ""
            set allFolders to every folder
            repeat with i from 1 to (count of allFolders)
                try
                    set out to out & (name of (item i of allFolders)) & linefeed
                end try
            end repeat
            return out
        end tell
        """
    }

    /// Parses the newline-delimited output of ``foldersScript()`` into an
    /// array of folder names, dropping blank lines.
    static func parseFolderLines(_ raw: String) -> [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Locale-stable parser for the `yyyy-MM-dd'T'HH:mm:ss` local-time
    /// stamps emitted by ``getScript(id:)``'s `isoDate` handler.
    static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()

    /// Parses the record-separated output of ``getScript(id:)`` into a
    /// ``NoteDetail``.
    ///
    /// Expects seven fields; returns `nil` when fewer are present (an
    /// empty result means Notes.app found no note with the requested id).
    /// The body fields are returned verbatim — newlines and tabs are
    /// preserved, nothing is trimmed. Empty date fields parse to `nil`.
    ///
    /// - Parameter raw: Raw script output.
    /// - Returns: The parsed detail, or `nil` when unparseable.
    static func parseNoteDetail(_ raw: String) -> NoteDetail? {
        let sep = Character(detailFieldSeparator)
        let fields = raw.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 7 else { return nil }
        // If a body somehow contained the separator, keep every trailing
        // piece as part of the HTML rather than dropping data.
        let html = fields[6...].joined(separator: detailFieldSeparator)
        return NoteDetail(
            id: fields[0],
            title: fields[1],
            folder: fields[2],
            plainText: fields[5],
            html: html,
            creationDate: fields[3].nonEmpty.flatMap { detailDateFormatter.date(from: $0) },
            modificationDate: fields[4].nonEmpty.flatMap { detailDateFormatter.date(from: $0) }
        )
    }


    /// Constructs a list-or-search AppleScript.
    ///
    /// When `query` is `nil` or empty, the script returns the most
    /// recently modified notes. When set, the script applies a
    /// case-insensitive `name contains` / `body contains` filter.
    ///
    /// > Note:
    /// > Iterating a `whose` filter result directly (e.g.
    /// > `repeat with n in (notes whose name contains "x")`) yields a
    /// > *specifier*, not a real reference. Notes.app rejects property
    /// > accesses like `container of n` on specifiers with:
    /// >
    /// >     Can't get name of container of item N of every note whose …
    /// >
    /// > The script works around this by materializing the filter into a
    /// > local variable and iterating by index, which gives a concrete
    /// > item reference.
    ///
    /// - Parameters:
    ///   - query: Substring to match, or `nil` for an unfiltered list.
    ///   - limit: Maximum notes to emit.
    ///   - offset: Number of leading matches to skip before emitting, for
    ///     paging. The repeat loop simply starts at `offset + 1`.
    /// - Returns: AppleScript source. Output format is one note per line:
    ///   `<id>\t<title>\t<folder>\t<snippet>\n`.
    static func listOrSearchScript(query: String?, limit: Int, offset: Int = 0) -> String {
        let filter: String
        if let query, !query.isEmpty {
            let esc = escapeForAppleScript(query)
            filter = "whose (name contains \"\(esc)\") or (body contains \"\(esc)\")"
        } else {
            filter = ""
        }
        let start = max(0, offset) + 1
        return """
        tell application "Notes"
            set out to ""
            set found to 0
            set matchedNotes to (every note \(filter))
            set total to count of matchedNotes
            repeat with i from \(start) to total
                if found \u{2265} \(limit) then exit repeat
                try
                    set n to item i of matchedNotes
                    set nid to id of n as string
                    set nname to name of n
                    set nbody to plaintext of n
                    if (length of nbody) > \(snippetPreviewMaxLength) then set nbody to (text 1 thru \(snippetPreviewMaxLength) of nbody) & "..."
                    set nfolder to ""
                    try
                        set nfolder to name of (container of n)
                    end try
                    set out to out & nid & "\t" & nname & "\t" & nfolder & "\t" & my oneLine(nbody) & linefeed
                    set found to found + 1
                end try
            end repeat
            return out
        end tell

        on oneLine(s)
            try
                set s to do shell script "printf %s " & quoted form of s & " | tr '\\t\\n\\r' '   '"
            end try
            return s
        end oneLine
        """
    }

    /// Parses the tab-delimited output produced by ``listOrSearchScript(query:limit:)``.
    ///
    /// Each line has four tab-separated fields:
    ///
    ///     <id>\t<title>\t<folder>\t<snippet>\n
    ///
    /// Lines with fewer than four fields are silently skipped — the
    /// AppleScript side is defensive about per-note failures and can
    /// emit a blank row if reading a note's body throws (for example,
    /// a locked note).
    ///
    /// - Parameter raw: Raw script output.
    /// - Returns: Parsed notes in source order.
    static func parseNoteLines(_ raw: String) -> [Note] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            return Note(id: fields[0], title: fields[1], snippet: fields[3], folder: fields[2])
        }
    }
}
