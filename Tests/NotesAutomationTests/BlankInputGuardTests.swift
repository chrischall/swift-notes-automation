import Foundation
import Testing
@testable import NotesAutomation

/// "Empty or whitespace-only" must include newlines and tabs: a query of
/// `"\n"` otherwise slips past the guard and scans every note's body.
@Suite("Blank-input guards")
struct BlankInputGuardTests {
    static let blanks = ["\n", "\r\n", " \n\t ", "\u{2028}"]

    @Test("NoteService.search treats newline-only queries as empty and runs no script", arguments: blanks)
    func serviceSearch(_ query: String) async throws {
        let runner = FakeAppleScriptRunner()
        let r = try await NoteService(runner: runner).search(query: query)
        #expect(r.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test("NoteStoreReader.search treats newline-only queries as empty", arguments: blanks)
    func readerSearch(_ query: String) async throws {
        let path = try NoteStoreFixture.create(notes: [
            .init(pk: 1, identifier: "U1", title: "Two\nlines", snippet: "a\nb",
                  folderPK: 100, markedForDeletion: false, modificationDate: 1),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)
        #expect(try await reader.search(query: query).isEmpty)
    }

    @Test("get/update/delete reject newline-only ids without running a script", arguments: blanks)
    func idGuards(_ id: String) async throws {
        let runner = FakeAppleScriptRunner()
        let svc = NoteService(runner: runner)
        await #expect(throws: NoteServiceError.invalidInput("id is required")) {
            _ = try await svc.get(id: id)
        }
        await #expect(throws: NoteServiceError.invalidInput("id is required")) {
            try await svc.update(id: id, title: "t")
        }
        await #expect(throws: NoteServiceError.invalidInput("id is required")) {
            try await svc.delete(id: id)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("create rejects a newline-only title without running a script", arguments: blanks)
    func titleGuard(_ title: String) async throws {
        let runner = FakeAppleScriptRunner()
        await #expect(throws: NoteServiceError.invalidInput("title is required")) {
            _ = try await NoteService(runner: runner).create(title: title, body: "b")
        }
        #expect(runner.calls.isEmpty)
    }
}
