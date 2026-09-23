import Foundation
import Testing
@testable import NotesAutomation

/// `NoteStoreReader.search` promises a case-insensitive substring match,
/// the same contract as the AppleScript path. SQLite's built-in `LOWER()`
/// folds ASCII only and `LIKE` treats `%` / `_` as wildcards, so both
/// have to be kept out of the match.
@Suite("NoteStoreReader search matching")
struct NoteStoreReaderSearchMatchingTests {

    private static let folders: [NoteStoreFixture.SeedFolder] = [.init(pk: 100, title: "Notes")]

    private static func note(_ pk: Int, _ title: String, _ snippet: String = "") -> NoteStoreFixture.SeedNote {
        .init(pk: pk, identifier: "UUID-\(pk)", title: title, snippet: snippet,
              folderPK: 100, markedForDeletion: false, modificationDate: Double(pk))
    }

    private func search(_ notes: [NoteStoreFixture.SeedNote], _ query: String) async throws -> [String] {
        let path = try NoteStoreFixture.create(folders: Self.folders, notes: notes)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)
        return try await reader.search(query: query).map(\.title)
    }

    @Test("search folds non-ASCII case in the title")
    func nonASCIITitle() async throws {
        let hits = try await search([Self.note(1, "ÄRGER im Büro"), Self.note(2, "Élan")], "ärger")
        #expect(hits == ["ÄRGER im Büro"])
        #expect(try await search([Self.note(2, "Élan")], "élan") == ["Élan"])
    }

    @Test("search folds non-ASCII case in the snippet")
    func nonASCIISnippet() async throws {
        let hits = try await search([Self.note(1, "Trip", "Übernachtung in ÖSTERREICH")], "österreich")
        #expect(hits == ["Trip"])
    }

    @Test("a lowercase non-ASCII note still matches an uppercase query")
    func uppercaseQuery() async throws {
        #expect(try await search([Self.note(1, "crème brûlée")], "CRÈME") == ["crème brûlée"])
    }

    @Test("% in the query is matched literally, not as a wildcard")
    func percentIsLiteral() async throws {
        let notes = [Self.note(1, "50 apples"), Self.note(2, "50% off")]
        #expect(try await search(notes, "50%") == ["50% off"])
    }

    @Test("_ in the query is matched literally, not as a single-char wildcard")
    func underscoreIsLiteral() async throws {
        let notes = [Self.note(1, "fooXbar"), Self.note(2, "foo_bar")]
        #expect(try await search(notes, "foo_bar") == ["foo_bar"])
    }

    @Test("backslash in the query is matched literally")
    func backslashIsLiteral() async throws {
        let notes = [Self.note(1, "C:\\temp"), Self.note(2, "C:temp")]
        #expect(try await search(notes, "C:\\") == ["C:\\temp"])
    }
}
