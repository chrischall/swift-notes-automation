import Foundation
import Testing
@testable import NotesAutomation

/// Tests for offset-based pagination on list/search, so callers can page
/// through a large note library rather than being capped at a single
/// `limit`.
@Suite("Pagination (offset)")
struct NotePaginationTests {
    // MARK: - Service (AppleScript)

    @Test("listOrSearchScript starts iterating past the offset")
    func scriptHonorsOffset() {
        // offset 5 → begin at item 6 (1-based AppleScript index).
        let s = NoteService.listOrSearchScript(query: nil, limit: 10, offset: 5)
        #expect(s.contains("from 6 "))
    }

    @Test("listOrSearchScript starts at item 1 when offset is 0")
    func scriptDefaultOffset() {
        let s = NoteService.listOrSearchScript(query: nil, limit: 10, offset: 0)
        #expect(s.contains("from 1 "))
    }

    @Test("list passes the offset into the generated script")
    func listOffsetDispatch() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let svc = NoteService(runner: runner)
        _ = try await svc.list(limit: 5, offset: 10)
        #expect(runner.calls[0].contains("from 11 "))
    }

    @Test("search passes the offset into the generated script")
    func searchOffsetDispatch() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let svc = NoteService(runner: runner)
        _ = try await svc.search(query: "note", limit: 5, offset: 3)
        #expect(runner.calls[0].contains("from 4 "))
    }

    // MARK: - Reader (SQLite)

    @Test("reader list pages through results with limit + offset")
    func readerListPaging() async throws {
        let path = try NoteStoreFixture.create()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)

        // Visible notes, newest-first by modification date:
        //   Cookies(3000), Meeting notes(2000), Orphan(1500), Shopping list(1000)
        let page1 = try await reader.list(limit: 2, offset: 0)
        #expect(page1.map(\.title) == ["Cookies", "Meeting notes"])

        let page2 = try await reader.list(limit: 2, offset: 2)
        #expect(page2.map(\.title) == ["Orphan", "Shopping list"])
    }

    @Test("reader search honors offset")
    func readerSearchPaging() async throws {
        let path = try NoteStoreFixture.create()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)

        // All fixture notes match "e" in title/snippet; page past the first.
        let all = try await reader.search(query: "o", limit: 10, offset: 0)
        #expect(all.count > 1)
        let paged = try await reader.search(query: "o", limit: 10, offset: 1)
        #expect(paged.map(\.title) == Array(all.map(\.title).dropFirst()))
    }
}
