import Foundation
import Testing
@testable import NotesAutomation

/// The pure body-windowing helpers consumers use to page a full note body
/// and to re-anchor a preview around a search match — plus the generated
/// search script's native match-anchored snippet.
@Suite("Body paging and match excerpts")
struct BodyExcerptTests {
    // MARK: - bodyPage

    @Test("bodyPage returns the whole body when nothing is clipped")
    func pageWhole() {
        let page = NoteService.bodyPage("hello world", offset: 0, maxChars: nil)
        #expect(page.text == "hello world")
        #expect(page.start == 0)
        #expect(page.end == 11)
        #expect(page.total == 11)
    }

    @Test("bodyPage clips at maxChars and reports the window")
    func pageClips() {
        let body = String(repeating: "a", count: 50) + String(repeating: "z", count: 50)
        let page = NoteService.bodyPage(body, offset: 0, maxChars: 50)
        #expect(page.text == String(repeating: "a", count: 50))
        #expect(page.end == 50)
        #expect(page.total == 100)
    }

    @Test("bodyPage pages from an offset")
    func pageOffset() {
        let body = "0123456789"
        let page = NoteService.bodyPage(body, offset: 4, maxChars: 3)
        #expect(page.text == "456")
        #expect(page.start == 4)
        #expect(page.end == 7)
    }

    @Test("bodyPage clamps an offset beyond the end to an empty window")
    func pageBeyondEnd() {
        let page = NoteService.bodyPage("short", offset: 99, maxChars: 10)
        #expect(page.text.isEmpty)
        #expect(page.start == 5)
        #expect(page.end == 5)
        #expect(page.total == 5)
    }

    @Test("bodyPage clamps a negative offset to zero")
    func pageNegativeOffset() {
        let page = NoteService.bodyPage("abc", offset: -5, maxChars: 2)
        #expect(page.text == "ab")
        #expect(page.start == 0)
    }

    @Test("bodyPage counts Characters, not UTF-8 bytes")
    func pageEmoji() {
        let body = "🎉🎉🎉ok"
        let page = NoteService.bodyPage(body, offset: 2, maxChars: 2)
        #expect(page.text == "🎉o")
        #expect(page.total == 5)
    }

    // MARK: - matchExcerpt

    @Test("matchExcerpt anchors the window around a deep match with ellipses")
    func excerptAnchors() {
        let body = String(repeating: "filler ", count: 100)
            + "Finn: bring cleats"
            + String(repeating: " tail", count: 100)
        let excerpt = NoteService.matchExcerpt(query: "Finn", in: body)
        let e = try! #require(excerpt)
        #expect(e.contains("Finn: bring cleats"))
        #expect(e.hasPrefix("…"))
        #expect(e.hasSuffix("…"))
        #expect(e.count <= NoteService.snippetPreviewMaxLength + 2)
    }

    @Test("matchExcerpt is case-insensitive")
    func excerptCaseInsensitive() {
        let excerpt = NoteService.matchExcerpt(query: "FINN", in: "ask finn about it")
        #expect(excerpt?.contains("finn") == true)
    }

    @Test("matchExcerpt returns nil when the body has no match")
    func excerptNoMatch() {
        #expect(NoteService.matchExcerpt(query: "Finn", in: "nothing here") == nil)
    }

    @Test("matchExcerpt normalizes newlines and tabs to single spaces")
    func excerptNormalizesWhitespace() {
        let excerpt = NoteService.matchExcerpt(query: "cleats", in: "Finn:\n\tbring cleats\nnow")
        #expect(excerpt == "Finn: bring cleats now")
    }

    @Test("matchExcerpt near the start has no leading ellipsis")
    func excerptAtStart() {
        let body = "Finn first" + String(repeating: " tail", count: 200)
        let e = try! #require(NoteService.matchExcerpt(query: "Finn", in: body))
        #expect(!e.hasPrefix("…"))
        #expect(e.hasSuffix("…"))
    }

    @Test("matchExcerpt survives emoji before the match")
    func excerptEmoji() {
        let body = String(repeating: "🎉", count: 400) + " Finn here"
        let e = try! #require(NoteService.matchExcerpt(query: "Finn", in: body))
        #expect(e.contains("Finn here"))
    }

    // MARK: - anchored search script

    @Test("search script anchors the snippet around the match")
    func searchScriptAnchors() {
        let script = NoteService.listOrSearchScript(query: "Finn", limit: 20)
        #expect(script.contains("anchoredSnippet"))
        #expect(script.contains("on anchoredSnippet(s, q, maxLen)"))
        #expect(script.contains("offset of q in s"))
    }

    @Test("search script escapes the query passed to the anchor handler")
    func searchScriptEscapesAnchorQuery() {
        let script = NoteService.listOrSearchScript(query: "say \"hi\"", limit: 5)
        #expect(script.contains("my anchoredSnippet(nbody, \"say \\\"hi\\\"\", "))
        #expect(!script.contains("anchoredSnippet(nbody, \"say \"hi\"\""))
    }

    @Test("list script keeps the plain head truncation and no anchor call")
    func listScriptUnanchored() {
        let script = NoteService.listOrSearchScript(query: nil, limit: 20)
        #expect(!script.contains("my anchoredSnippet"))
        #expect(script.contains("text 1 thru \(NoteService.snippetPreviewMaxLength)"))
    }
}
