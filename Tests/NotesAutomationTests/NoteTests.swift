import Testing
@testable import NotesAutomation

@Suite("Note")
struct NoteTests {
    @Test("initializer assigns all fields verbatim")
    func initAssignsFields() {
        let note = Note(id: "x-coredata://n/1", title: "Title", snippet: "Snip", folder: "Folder")
        #expect(note.id == "x-coredata://n/1")
        #expect(note.title == "Title")
        #expect(note.snippet == "Snip")
        #expect(note.folder == "Folder")
    }

    @Test("equality compares every stored field")
    func equatable() {
        let base = Note(id: "1", title: "T", snippet: "S", folder: "F")
        #expect(base == Note(id: "1", title: "T", snippet: "S", folder: "F"))
        #expect(base != Note(id: "2", title: "T", snippet: "S", folder: "F"))
        #expect(base != Note(id: "1", title: "X", snippet: "S", folder: "F"))
        #expect(base != Note(id: "1", title: "T", snippet: "X", folder: "F"))
        #expect(base != Note(id: "1", title: "T", snippet: "S", folder: "X"))
    }

    @Test("Hashable collapses equal values in a Set")
    func hashable() {
        let a = Note(id: "1", title: "T", snippet: "S", folder: "F")
        let b = Note(id: "1", title: "T", snippet: "S", folder: "F")
        let c = Note(id: "2", title: "T", snippet: "S", folder: "F")
        var set: Set<Note> = []
        set.insert(a)
        set.insert(b)
        set.insert(c)
        #expect(set.count == 2)
    }

    @Test("Identifiable surfaces the opaque Notes.app id")
    func identifiable() {
        let note = Note(id: "x-coredata://n/42", title: "T", snippet: "S", folder: "F")
        let id: Note.ID = note.id
        #expect(id == "x-coredata://n/42")
    }
}
