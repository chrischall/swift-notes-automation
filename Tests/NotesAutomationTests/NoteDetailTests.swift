import Foundation
import Testing
@testable import NotesAutomation

/// Tests for the full-body read path: ``NoteDetail`` and
/// ``NoteService/get(id:)``. Unlike list/search — which return a
/// truncated ``Note/snippet`` — `get` returns the note's complete,
/// untruncated body in both plain-text and HTML form, plus dates.
@Suite("NoteDetail / get")
struct NoteDetailTests {
    // A record separator (ASCII 0x1E) delimits `get`'s fields because the
    // body itself contains newlines and tabs, so the tab/newline scheme
    // used by list/search can't be reused here.
    private var sep: String { NoteService.detailFieldSeparator }

    // MARK: - NoteDetail value type

    @Test("NoteDetail carries full plain-text and HTML bodies plus dates")
    func detailFields() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let modified = Date(timeIntervalSince1970: 1_700_000_500)
        let d = NoteDetail(
            id: "x-coredata://store/ICNote/p1",
            title: "Trip plan",
            folder: "Travel",
            plainText: "Day 1\nDay 2",
            html: "<div>Day 1</div>",
            creationDate: created,
            modificationDate: modified
        )
        #expect(d.id == "x-coredata://store/ICNote/p1")
        #expect(d.title == "Trip plan")
        #expect(d.folder == "Travel")
        #expect(d.plainText == "Day 1\nDay 2")
        #expect(d.html == "<div>Day 1</div>")
        #expect(d.creationDate == created)
        #expect(d.modificationDate == modified)
    }

    // MARK: - getScript generation

    @Test("getScript references plaintext, body (HTML), and both dates")
    func getScriptShape() {
        let s = NoteService.getScript(id: "x-coredata://notes/42")
        #expect(s.contains("tell application \"Notes\""))
        #expect(s.contains("note id \"x-coredata://notes/42\""))
        #expect(s.contains("plaintext of"))
        #expect(s.contains("body of"))
        #expect(s.contains("creation date"))
        #expect(s.contains("modification date"))
    }

    @Test("getScript escapes backslashes and quotes in the id")
    func getScriptEscapesId() {
        let s = NoteService.getScript(id: "weird\"id\\x")
        #expect(s.contains("weird\\\"id\\\\x"))
    }

    // MARK: - parseNoteDetail

    @Test("parseNoteDetail preserves newlines and tabs in the body")
    func parseBodyPreservesWhitespace() {
        let raw = [
            "x-coredata://n/1", "Trip plan", "Travel",
            "2024-03-01T09:30:00", "2024-03-02T14:00:00",
            "Line1\nLine2\tTabbed\n", "<div>Line1</div>",
        ].joined(separator: sep)
        let d = NoteService.parseNoteDetail(raw)
        #expect(d?.id == "x-coredata://n/1")
        #expect(d?.title == "Trip plan")
        #expect(d?.folder == "Travel")
        #expect(d?.plainText == "Line1\nLine2\tTabbed\n")
        #expect(d?.html == "<div>Line1</div>")
        #expect(d?.creationDate != nil)
        #expect(d?.modificationDate != nil)
    }

    @Test("parseNoteDetail treats empty date/folder fields as nil/empty")
    func parseEmptyOptionalFields() {
        let raw = [
            "id", "Title", "", "", "", "just a body", "<p>just a body</p>",
        ].joined(separator: sep)
        let d = NoteService.parseNoteDetail(raw)
        #expect(d?.folder == "")
        #expect(d?.creationDate == nil)
        #expect(d?.modificationDate == nil)
        #expect(d?.plainText == "just a body")
    }

    @Test("parseNoteDetail returns nil for output with too few fields")
    func parseMalformed() {
        #expect(NoteService.parseNoteDetail("only\u{001E}two\u{001E}fields") == nil)
        #expect(NoteService.parseNoteDetail("") == nil)
    }

    // MARK: - get dispatch

    @Test("get rejects empty / whitespace-only ids without running a script")
    func getRejectsEmpty() async throws {
        let runner = FakeAppleScriptRunner()
        let svc = NoteService(runner: runner)
        await #expect(throws: NoteServiceError.self) {
            _ = try await svc.get(id: "   ")
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("get returns the full untruncated body from the runner output")
    func getDispatches() async throws {
        let runner = FakeAppleScriptRunner()
        let longBody = String(repeating: "sentence. ", count: 500) // ~5000 chars
        runner.queue([
            "x-coredata://n/1", "Essay", "Work",
            "2024-01-01T00:00:00", "2024-01-02T12:00:00",
            longBody, "<h1>Essay</h1>",
        ].joined(separator: sep))
        let svc = NoteService(runner: runner)

        let d = try await svc.get(id: "x-coredata://n/1")

        #expect(d.title == "Essay")
        #expect(d.plainText == longBody)
        #expect(d.plainText.count > 200) // proves it is NOT snippet-truncated
        #expect(d.html == "<h1>Essay</h1>")
        #expect(runner.calls[0].contains("plaintext of"))
    }

    @Test("get throws scriptFailure when the output can't be parsed")
    func getParseFailure() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("garbage without separators")
        let svc = NoteService(runner: runner)
        await #expect(throws: NoteServiceError.self) {
            _ = try await svc.get(id: "x-coredata://n/1")
        }
    }

    @Test("get propagates runner errors")
    func getPropagates() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Can't get note id \"bogus\"")
        let svc = NoteService(runner: runner)
        await #expect(throws: AppleScriptError.self) {
            _ = try await svc.get(id: "bogus")
        }
    }
}
