import Testing
@testable import NotesAutomation

@Suite("String helpers")
struct StringHelpersTests {
    @Test("nonEmpty returns self for non-empty strings")
    func nonEmptyPassesThrough() {
        #expect("hello".nonEmpty == "hello")
    }

    @Test("nonEmpty treats whitespace as non-empty")
    func nonEmptyIsByteLength() {
        #expect(" ".nonEmpty == " ")
        #expect("\t\n".nonEmpty == "\t\n")
    }

    @Test("nonEmpty returns nil for the empty string")
    func emptyMapsToNil() {
        #expect("".nonEmpty == nil)
    }

    @Test("nonEmpty chains cleanly with nil-coalescing")
    func nonEmptyCoalesces() {
        let explicit = ""
        let envDefault = "fallback"
        #expect((explicit.nonEmpty ?? envDefault) == "fallback")

        let real = "value"
        #expect((real.nonEmpty ?? envDefault) == "value")
    }
}
