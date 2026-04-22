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
/// let id     = try await notes.create(title: "Plan", body: "…", folder: "Work")
/// ```
///
/// ## Scope
///
/// The service exposes the subset of Notes.app's AppleScript surface that
/// maps cleanly to a flat list of notes: ``list(limit:)``,
/// ``search(query:limit:)``, ``create(title:body:folder:)``, and
/// ``delete(id:)``. Folder structure is represented only by the `folder`
/// string on each ``Note``; there is no separate folder model. Update is
/// intentionally omitted — contributions welcome.
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

    // MARK: - List / search

    /// Returns the most-recently-modified notes, up to `limit`.
    ///
    /// - Parameter limit: Maximum number of notes to return. Defaults to
    ///   `20`.
    /// - Returns: Notes in Notes.app's native iteration order, which is
    ///   typically most-recently-modified first. The array is empty when
    ///   the user has no notes.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when Notes.app is not
    ///   running or Automation permission is denied.
    public func list(limit: Int = 20) async throws -> [Note] {
        let source = Self.listOrSearchScript(query: nil, limit: limit)
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
    /// - Returns: Matching notes, up to `limit`.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when Notes.app is not
    ///   running or Automation permission is denied.
    public func search(query: String, limit: Int = 20) async throws -> [Note] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let source = Self.listOrSearchScript(query: query, limit: limit)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    // MARK: - Create

    /// Creates a new note with the given title and body.
    ///
    /// The body is wrapped in Notes.app's HTML-ish format with the title
    /// as an `<h1>` so the UI shows a proper heading. Quotes in `title`,
    /// `body`, and `folder` are escaped before they reach AppleScript.
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
        // the UI renders a proper header. Only quotes need escaping for the
        // AppleScript string literals — backslashes and angle brackets are
        // passed through intentionally.
        let esc: (String) -> String = { $0.replacingOccurrences(of: "\"", with: "\\\"") }
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

    /// Constructs a delete-by-id AppleScript.
    ///
    /// Looks up the note via `note id "…"`, which references Notes.app's
    /// Core Data URI. If the note doesn't exist, AppleScript raises at
    /// runtime — callers surface that as ``AppleScriptError/runtime(_:)``.
    ///
    /// - Parameter id: The note's opaque id. Double-quotes are escaped
    ///   defensively before interpolation.
    /// - Returns: AppleScript source.
    static func deleteScript(id: String) -> String {
        let esc = id.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Notes"
            delete note id "\(esc)"
        end tell
        """
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
    /// - Returns: AppleScript source. Output format is one note per line:
    ///   `<id>\t<title>\t<folder>\t<snippet>\n`.
    static func listOrSearchScript(query: String?, limit: Int) -> String {
        let filter: String
        if let query, !query.isEmpty {
            let esc = query.replacingOccurrences(of: "\"", with: "\\\"")
            filter = "whose (name contains \"\(esc)\") or (body contains \"\(esc)\")"
        } else {
            filter = ""
        }
        return """
        tell application "Notes"
            set out to ""
            set found to 0
            set matchedNotes to (every note \(filter))
            set total to count of matchedNotes
            repeat with i from 1 to total
                if found \u{2265} \(limit) then exit repeat
                try
                    set n to item i of matchedNotes
                    set nid to id of n as string
                    set nname to name of n
                    set nbody to plaintext of n
                    if (length of nbody) > 200 then set nbody to (text 1 thru 200 of nbody) & "..."
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
