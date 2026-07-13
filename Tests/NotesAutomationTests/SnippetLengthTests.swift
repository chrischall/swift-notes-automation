import Foundation
import Testing
@testable import NotesAutomation

/// The list/search snippet preview length is a named constant, not a magic
/// number, and the generated AppleScript truncates to it.
@Suite("Snippet preview length")
struct SnippetLengthTests {
    @Test("snippetPreviewMaxLength is a sensible preview size")
    func constantExists() {
        // A scannable preview — longer than a sentence, far short of a full
        // body (that's what `get(id:)` is for).
        #expect(NoteService.snippetPreviewMaxLength >= 300)
        #expect(NoteService.snippetPreviewMaxLength <= 400)
    }

    @Test("listOrSearchScript truncates to the named constant, not a literal")
    func scriptUsesConstant() {
        let n = NoteService.snippetPreviewMaxLength
        let script = NoteService.listOrSearchScript(query: nil, limit: 20)
        #expect(script.contains("> \(n)"))
        #expect(script.contains("text 1 thru \(n)"))
    }
}
