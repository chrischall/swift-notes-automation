import Foundation

public enum NoteServiceError: Error, Equatable, Sendable {
    case scriptFailure(String)
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

    public func list(limit: Int = 20) async throws -> [Note] {
        let source = Self.listOrSearchScript(query: nil, limit: limit)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    public func search(query: String, limit: Int = 20) async throws -> [Note] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let source = Self.listOrSearchScript(query: query, limit: limit)
        let raw = try await runner.run(source: source)
        return Self.parseNoteLines(raw)
    }

    // MARK: - Create

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
            repeat with n in (notes \(filter))
                if found \u{2265} \(limit) then exit repeat
                try
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

    /// Parse tab-delimited note records.
    static func parseNoteLines(_ raw: String) -> [Note] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            return Note(id: fields[0], title: fields[1], snippet: fields[3], folder: fields[2])
        }
    }
}
