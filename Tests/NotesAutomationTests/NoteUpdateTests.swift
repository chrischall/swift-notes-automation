import Foundation
import Testing
@testable import NotesAutomation

/// Tests for ``NoteService/update(id:title:body:folder:)`` — editing an
/// existing note's title, body, and/or containing folder in place.
@Suite("NoteService.update")
struct NoteUpdateTests {
    @Test("update rejects empty / whitespace-only ids")
    func rejectsEmptyId() async throws {
        let svc = NoteService(runner: FakeAppleScriptRunner())
        await #expect(throws: NoteServiceError.self) {
            try await svc.update(id: "  ", title: "New")
        }
    }

    @Test("update with no fields to change throws invalidInput")
    func rejectsNoOp() async throws {
        let runner = FakeAppleScriptRunner()
        let svc = NoteService(runner: runner)
        await #expect(throws: NoteServiceError.self) {
            try await svc.update(id: "x-coredata://n/1")
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("updateScript sets the name when a title is given")
    func scriptSetsName() {
        let s = NoteService.updateScript(
            id: "x-coredata://n/1", title: "Renamed", body: nil, folder: nil
        )
        #expect(s.contains("note id \"x-coredata://n/1\""))
        #expect(s.contains("set name of"))
        #expect(s.contains("Renamed"))
        #expect(!s.contains("set body of"))
        #expect(!s.contains("move "))
    }

    @Test("updateScript sets the body when a body is given")
    func scriptSetsBody() {
        let s = NoteService.updateScript(
            id: "x-coredata://n/1", title: nil, body: "fresh <b>content</b>", folder: nil
        )
        #expect(s.contains("set body of"))
        #expect(s.contains("fresh <b>content</b>"))
        #expect(!s.contains("set name of"))
    }

    @Test("updateScript moves the note to a folder, creating it if absent")
    func scriptMovesFolder() {
        let s = NoteService.updateScript(
            id: "x-coredata://n/1", title: nil, body: nil, folder: "Archive"
        )
        #expect(s.contains("Archive"))
        #expect(s.contains("move "))
        // Folder is created when it does not already exist.
        #expect(s.contains("make new folder"))
    }

    @Test("updateScript escapes backslashes and quotes in every field")
    func scriptEscapes() {
        let s = NoteService.updateScript(
            id: "weird\"id", title: "ti\"tle", body: "bo\\dy", folder: "fol\"der"
        )
        #expect(s.contains("weird\\\"id"))
        #expect(s.contains("ti\\\"tle"))
        #expect(s.contains("bo\\\\dy"))
        #expect(s.contains("fol\\\"der"))
    }

    @Test("update dispatches the generated script to the runner")
    func dispatches() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let svc = NoteService(runner: runner)

        try await svc.update(id: "x-coredata://n/1", title: "T", body: "B", folder: "F")

        #expect(runner.calls.count == 1)
        let src = runner.calls[0]
        #expect(src.contains("set name of"))
        #expect(src.contains("set body of"))
        #expect(src.contains("move "))
    }

    @Test("update propagates runner errors")
    func propagates() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Can't get note id \"bogus\"")
        let svc = NoteService(runner: runner)
        await #expect(throws: AppleScriptError.self) {
            try await svc.update(id: "bogus", title: "T")
        }
    }
}
