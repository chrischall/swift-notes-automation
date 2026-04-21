import Foundation
import Testing
@testable import NotesAutomation

@Suite("NoteService")
struct NoteServiceTests {
    @Test("parseNoteLines returns notes from tab-delimited output")
    func parseNotes() {
        let raw = "id-1\tShopping\tHome\tMilk, eggs, bread\n"
            + "id-2\tMeeting notes\t\tDiscussed Q2 plan\n"
        let notes = NoteService.parseNoteLines(raw)
        #expect(notes.count == 2)
        #expect(notes[0].title == "Shopping")
        #expect(notes[0].folder == "Home")
        #expect(notes[0].snippet.starts(with: "Milk"))
        #expect(notes[1].folder == "")
    }

    @Test("parseNoteLines skips malformed rows")
    func parseSkipBadRows() {
        let raw = "only one field\n"
            + "id-1\tTitle\tFolder\tSnippet\n"
        let notes = NoteService.parseNoteLines(raw)
        #expect(notes.count == 1)
        #expect(notes[0].title == "Title")
    }

    @Test("listOrSearchScript omits the filter when query is nil")
    func listScriptNoFilter() {
        let script = NoteService.listOrSearchScript(query: nil, limit: 20)
        #expect(!script.contains("whose"))
        #expect(script.contains("notes "))
    }

    @Test("listOrSearchScript adds a name+body contains filter when query is given")
    func searchScriptFilter() {
        let script = NoteService.listOrSearchScript(query: "groceries", limit: 10)
        #expect(script.contains("name contains \"groceries\""))
        #expect(script.contains("body contains \"groceries\""))
    }

    @Test("search returns [] without running a script for empty query")
    func searchEmpty() async throws {
        let runner = FakeAppleScriptRunner()
        let svc = NoteService(runner: runner)
        let r = try await svc.search(query: "  ")
        #expect(r.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test("create requires a non-empty title")
    func createValidation() async throws {
        let svc = NoteService(runner: FakeAppleScriptRunner())
        await #expect(throws: NoteServiceError.self) {
            _ = try await svc.create(title: "  ", body: "some body")
        }
    }

    @Test("create passes title, body, and folder into the script")
    func createDispatches() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("x-coredata://notes/1")
        let svc = NoteService(runner: runner)

        let id = try await svc.create(title: "Weekly plan", body: "talk about Q3", folder: "Work")

        #expect(id == "x-coredata://notes/1")
        let src = runner.calls[0]
        #expect(src.contains("Weekly plan"))
        #expect(src.contains("talk about Q3"))
        #expect(src.contains("Work"))
    }
}
