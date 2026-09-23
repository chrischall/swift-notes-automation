import Foundation
import Testing
@testable import NotesAutomation

/// Public numeric inputs (`limit`, `offset`, `maxChars`, `maxLength`) are
/// often fed straight from MCP tool arguments. An out-of-range value must
/// clamp, never trap — a trap kills the whole host process.
@Suite("Input bounds")
struct InputBoundsTests {

    private func withReader(_ body: (NoteStoreReader) async throws -> Void) async throws {
        let path = try NoteStoreFixture.create()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await body(try NoteStoreReader(path: path))
    }

    // MARK: - NoteStoreReader

    @Test("reader list with a limit past Int32 returns every note instead of trapping")
    func readerHugeLimit() async throws {
        try await withReader { reader in
            let r1 = try await reader.list(limit: 5_000_000_000)
            #expect(r1.count == 4)
            let r2 = try await reader.list(limit: .max)
            #expect(r2.count == 4)
        }
    }

    @Test("reader list with an offset past Int32 returns [] instead of trapping")
    func readerHugeOffset() async throws {
        try await withReader { reader in
            let r3 = try await reader.list(limit: 10, offset: 5_000_000_000)
            #expect(r3.isEmpty)
            let r4 = try await reader.search(query: "e", limit: 10, offset: .max)
            #expect(r4.isEmpty)
        }
    }

    @Test("reader treats a negative limit as zero, not SQLite's LIMIT -1 (unlimited)")
    func readerNegativeLimit() async throws {
        try await withReader { reader in
            let r5 = try await reader.list(limit: -1)
            #expect(r5.isEmpty)
            let r6 = try await reader.search(query: "e", limit: -1)
            #expect(r6.isEmpty)
            let r7 = try await reader.list(limit: .min)
            #expect(r7.isEmpty)
        }
    }

    // MARK: - listOrSearchScript

    @Test("listOrSearchScript survives offset = Int.max")
    func scriptHugeOffset() {
        let s = NoteService.listOrSearchScript(query: nil, limit: 10, offset: .max)
        #expect(s.contains("repeat with i from "))
    }

    @Test("listOrSearchScript clamps a negative limit to zero")
    func scriptNegativeLimit() {
        let s = NoteService.listOrSearchScript(query: nil, limit: -5)
        #expect(s.contains("if found \u{2265} 0 then exit repeat"))
    }

    // MARK: - bodyPage

    @Test("bodyPage with maxChars = Int.max returns the rest of the body")
    func bodyPageHugeMaxChars() {
        let page = NoteService.bodyPage("hello world", offset: 6, maxChars: .max)
        #expect(page.text == "world")
        #expect(page.end == 11)
    }

    @Test("bodyPage with offset = Int.max and maxChars = Int.max is an empty tail window")
    func bodyPageHugeBoth() {
        let page = NoteService.bodyPage("abc", offset: .max, maxChars: .max)
        #expect(page.text.isEmpty)
        #expect(page.start == 3 && page.end == 3)
    }

    // MARK: - matchExcerpt

    @Test("matchExcerpt with a negative maxLength does not trap")
    func excerptNegativeMaxLength() {
        let e = NoteService.matchExcerpt(query: "Finn", in: "ask Finn about cleats", maxLength: -10)
        #expect(e != nil)
    }

    @Test("matchExcerpt with maxLength = Int.max returns the whole body")
    func excerptHugeMaxLength() {
        let e = NoteService.matchExcerpt(query: "Finn", in: "ask Finn about cleats", maxLength: .max)
        #expect(e == "ask Finn about cleats")
    }
}
