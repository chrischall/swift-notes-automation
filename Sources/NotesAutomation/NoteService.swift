import Foundation

/// Errors surfaced by `NoteService` operations.
public enum NoteServiceError: Error, Equatable, Sendable {
    /// AppleScript ran but Notes.app reported a non-success result, or the
    /// returned payload couldn't be parsed. The string carries context
    /// for debugging.
    case scriptFailure(String)
    /// Caller passed an empty / whitespace-only string for a required
    /// parameter (title, typically).
    case invalidInput(String)
}

/// Notes.app wrapper. AppleScript is the only public interface — same as
/// the Node port. Returns notes as a flat list; folder structure is
/// represented only by the `folder` string on each note.
public struct NoteService: Sendable {
    private let runner: any AppleScriptRunner

    public init(runner: any AppleScriptRunner) {
        self.runner = runner
    }

    // MARK: - List / Search

    /// Returns the most-recently-modified notes, up to `limit`.
    ///
    /// - Parameter limit: Maximum notes to return (default 20).
    /// - Returns: Notes in Notes.app's native iteration order (typically
    ///   most-recently-modified first).
    /// - Throws: `AppleScriptError.runtime` if Notes is not running or
    ///   Automation permission is denied.
    public func list(limit: Int = 20) async throws -> [Note] {
        let source = Self.listOrSearchScript(query: nil, limit: limit)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    /// Searches notes by name or body substring. Case-insensitive;
    /// matches either `name` OR `body` via Notes.app's `whose` clause.
    ///
    /// - Parameters:
    ///   - query: Substring to match. Empty / whitespace-only returns `[]`
    ///     without running a script.
    ///   - limit: Maximum results (default 20).
    public func search(query: String, limit: Int = 20) async throws -> [Note] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let source = Self.listOrSearchScript(query: query, limit: limit)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    // MARK: - Create

    /// Creates a new note with `title` and `body`. The body is wrapped
    /// in Notes.app's HTML-ish format with the title as `<h1>` so the
    /// UI shows a proper heading.
    ///
    /// - Parameters:
    ///   - title: Note name. Required, non-empty.
    ///   - body: Note body. HTML allowed but quotes/newlines are
    ///     escaped for you.
    ///   - folder: Optional folder name to place the note in. If the
    ///     folder doesn't exist, it's created.
    /// - Returns: The newly-created note's opaque id (matches the
    ///   `id` on `Note` values returned by `list` / `search`).
    public func create(title: String, body: String, folder: String? = nil) async throws -> String {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NoteServiceError.invalidInput("title is required")
        }
        // Notes.app treats note body as HTML-ish; combine title + body so the
        // UI shows a proper header. Escape quotes.
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

    // MARK: - Script generation

    /// Construct a list/search script. When `query` is nil, returns most
    /// recently modified notes; when set, filters by name or body contains.
    ///
    /// Implementation detail: iterating a `whose` filter result directly
    /// (e.g. `repeat with n in (notes whose name contains "x")`) gives you
    /// a specifier, not a real reference — and Notes rejects property
    /// accesses like `container of n` on specifiers with:
    ///
    ///     Can't get name of container of item N of every note whose …
    ///
    /// We dodge this by pulling the filtered set into a variable first and
    /// then iterating by index into a concrete item reference.
    static func listOrSearchScript(query: String?, limit: Int) -> String {
        let filter: String
        if let q = query, !q.isEmpty {
            let esc = q.replacingOccurrences(of: "\"", with: "\\\"")
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

    /// Parse the tab-delimited output produced by `listOrSearchScript`.
    /// Format is one note per line, four fields separated by `\t`:
    ///
    ///     <id>\t<title>\t<folder>\t<snippet>\n
    ///
    /// Malformed lines (fewer than 4 fields) are silently skipped — the
    /// AppleScript side is defensive about errors but can emit a blank
    /// row if reading a note's body throws.
    static func parseNoteLines(_ raw: String) -> [Note] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            return Note(id: fields[0], title: fields[1], snippet: fields[3], folder: fields[2])
        }
    }
}
