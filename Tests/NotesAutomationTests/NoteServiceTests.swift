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
        // Should materialize `every note` to a local variable so we can
        // iterate by index (see the implementation note about specifier
        // references rejecting `container` accesses).
        #expect(script.contains("every note"))
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

    // ─── parseNoteLines — edge cases ───────────────────────────────────────

    @Test("parseNoteLines handles empty input")
    func parseEmpty() {
        #expect(NoteService.parseNoteLines("").isEmpty)
        #expect(NoteService.parseNoteLines("\n\n\n").isEmpty)
    }

    @Test("parseNoteLines preserves unicode in titles, folders, and snippets")
    func parseUnicode() {
        let raw = "id-1\tメモ 🎉\tフォルダ\tソーカーの練習メモ\n"
        let notes = NoteService.parseNoteLines(raw)
        #expect(notes.count == 1)
        #expect(notes[0].title == "メモ 🎉")
        #expect(notes[0].folder == "フォルダ")
        #expect(notes[0].snippet.contains("ソーカー"))
    }

    @Test("parseNoteLines preserves trailing tab/empty fields correctly")
    func parseTrailingEmpty() {
        // Empty snippet field, no trailing content
        let raw = "id-1\tTitle\tFolder\t\n"
        let notes = NoteService.parseNoteLines(raw)
        #expect(notes.count == 1)
        #expect(notes[0].snippet == "")
    }

    @Test("parseNoteLines returns multiple notes in source order")
    func parseOrder() {
        let raw = "id-a\tA\tF\tx\n"
            + "id-b\tB\tF\ty\n"
            + "id-c\tC\tF\tz\n"
        let notes = NoteService.parseNoteLines(raw)
        #expect(notes.map(\.id) == ["id-a", "id-b", "id-c"])
    }

    // ─── listOrSearchScript — edge cases ───────────────────────────────────

    @Test("listOrSearchScript embeds the caller's limit literally")
    func listScriptLimit() {
        let script = NoteService.listOrSearchScript(query: nil, limit: 7)
        // `found ≥ 7 then exit repeat`
        #expect(script.contains("\u{2265} 7"))
    }

    @Test("listOrSearchScript escapes double-quotes in the search query")
    func searchScriptEscapesQuery() {
        let script = NoteService.listOrSearchScript(query: "she said \"hi\"", limit: 10)
        // Should end up as  contains "she said \"hi\""  in AppleScript source
        #expect(script.contains("she said \\\"hi\\\""))
    }

    @Test("listOrSearchScript: empty query behaves like nil (unfiltered)")
    func searchEmptyStringQuery() {
        let script = NoteService.listOrSearchScript(query: "", limit: 10)
        #expect(!script.contains("whose"))
    }

    // ─── list / search dispatch ────────────────────────────────────────────

    @Test("list returns parsed results from the runner output")
    func listDispatches() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id-1\tTo-do\tWork\tThings to do\n")
        let svc = NoteService(runner: runner)

        let notes = try await svc.list(limit: 5)

        #expect(notes.count == 1)
        #expect(notes[0].title == "To-do")
        // limit should flow into the generated script
        #expect(runner.calls[0].contains("\u{2265} 5"))
    }

    @Test("list propagates runner errors")
    func listPropagatesErrors() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Not authorized to send Apple events to Notes.")
        let svc = NoteService(runner: runner)

        await #expect(throws: AppleScriptError.self) {
            _ = try await svc.list()
        }
    }

    @Test("search delegates with the limit")
    func searchLimit() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let svc = NoteService(runner: runner)

        _ = try await svc.search(query: "receipt", limit: 3)

        let src = runner.calls[0]
        #expect(src.contains("name contains \"receipt\""))
        #expect(src.contains("\u{2265} 3"))
    }

    @Test("search propagates runner errors")
    func searchPropagates() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Notes got an error")
        let svc = NoteService(runner: runner)

        await #expect(throws: AppleScriptError.self) {
            _ = try await svc.search(query: "x")
        }
    }

    // ─── create — more edge cases ──────────────────────────────────────────

    @Test("create works without a folder argument")
    func createNoFolder() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("x-coredata://new")
        let svc = NoteService(runner: runner)

        let id = try await svc.create(title: "Quick note", body: "just a thought")

        #expect(id == "x-coredata://new")
        let src = runner.calls[0]
        // With no folder, the script creates the note at the top level —
        // not inside any folder reference.
        #expect(!src.contains("first folder whose name is"))
        #expect(src.contains("Quick note"))
    }

    @Test("create escapes double-quotes in title and body")
    func createEscapesQuotes() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id")
        let svc = NoteService(runner: runner)

        _ = try await svc.create(title: "She said \"hi\"", body: "<b>bold</b> & \"quoted\"")

        let src = runner.calls[0]
        // Title + body should be escaped inside AppleScript string literals
        #expect(src.contains("She said \\\"hi\\\""))
        #expect(src.contains("\\\"quoted\\\""))
    }

    @Test("create with empty body still sends a valid script")
    func createEmptyBody() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id")
        let svc = NoteService(runner: runner)

        _ = try await svc.create(title: "Empty", body: "")

        let src = runner.calls[0]
        #expect(src.contains("Empty"))
        // No crash from empty string; body ends up as an empty string literal
        #expect(src.contains("make new note"))
    }

    @Test("create trims the id returned by AppleScript")
    func createTrimsId() async throws {
        let runner = FakeAppleScriptRunner()
        // AppleScript often tacks on trailing whitespace or newlines
        runner.queue("  x-coredata://notes/42  \n")
        let svc = NoteService(runner: runner)

        let id = try await svc.create(title: "X", body: "")

        #expect(id == "x-coredata://notes/42")
    }

    @Test("create propagates runner errors")
    func createPropagates() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Notes.app not running")
        let svc = NoteService(runner: runner)

        await #expect(throws: AppleScriptError.self) {
            _ = try await svc.create(title: "X", body: "Y")
        }
    }

    // ─── delete ────────────────────────────────────────────────────────────

    @Test("deleteScript targets the note by id and calls delete")
    func deleteScriptShape() {
        let script = NoteService.deleteScript(id: "x-coredata://notes/abc")
        #expect(script.contains("tell application \"Notes\""))
        // Looks up the note by id, then issues a delete.
        #expect(script.contains("x-coredata://notes/abc"))
        #expect(script.contains("delete"))
    }

    @Test("deleteScript escapes double-quotes in the id")
    func deleteScriptEscapesQuotes() {
        // IDs from Notes are opaque URIs but we still treat them as strings
        // and interpolate into AppleScript literals — escape defensively.
        let script = NoteService.deleteScript(id: "weird\"id")
        #expect(script.contains("weird\\\"id"))
    }

    @Test("delete rejects empty / whitespace-only ids")
    func deleteRejectsEmpty() async throws {
        let svc = NoteService(runner: FakeAppleScriptRunner())
        await #expect(throws: NoteServiceError.self) {
            try await svc.delete(id: "")
        }
        await #expect(throws: NoteServiceError.self) {
            try await svc.delete(id: "   ")
        }
    }

    @Test("delete dispatches the script to the runner")
    func deleteDispatches() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let svc = NoteService(runner: runner)

        try await svc.delete(id: "x-coredata://notes/42")

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains("x-coredata://notes/42"))
        #expect(runner.calls[0].contains("delete"))
    }

    @Test("delete propagates runner errors")
    func deletePropagates() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Can't get note id \"bogus\"")
        let svc = NoteService(runner: runner)

        await #expect(throws: AppleScriptError.self) {
            try await svc.delete(id: "bogus")
        }
    }
}
