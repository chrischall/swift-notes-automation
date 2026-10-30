import Foundation
@testable import NotesAutomation
import Testing

@Suite("Error types")
struct ErrorTests {
    // MARK: - AppleScriptError

    @Test("AppleScriptError equality discriminates cases and associated values")
    func appleScriptEquatable() {
        #expect(AppleScriptError.runtime("x") == .runtime("x"))
        #expect(AppleScriptError.runtime("x") != .runtime("y"))
        #expect(AppleScriptError.compile("x") == .compile("x"))
        #expect(AppleScriptError.compile("x") != .compile("y"))
        #expect(AppleScriptError.runtime("x") != .compile("x"))
    }

    @Test("AppleScriptError.errorDescription labels each case")
    func appleScriptLocalizedError() {
        #expect(AppleScriptError.runtime("oops").errorDescription
            == "AppleScript runtime error: oops")
        #expect(AppleScriptError.compile("nope").errorDescription
            == "AppleScript compile error: nope")
    }

    // MARK: - NotesError

    @Test("NotesError equality discriminates cases and associated values")
    func notesErrorEquatable() {
        #expect(NotesError.invalidInput("x") == .invalidInput("x"))
        #expect(NotesError.invalidInput("x") != .invalidInput("y"))
        #expect(NotesError.scriptFailure("x") == .scriptFailure("x"))
        #expect(NotesError.scriptFailure("x") != .invalidInput("x"))
        #expect(NotesError.appleScript(.runtime("x")) == .appleScript(.runtime("x")))
        #expect(NotesError.appleScript(.runtime("x")) != .appleScript(.compile("x")))
        #expect(NotesError.appleScript(.runtime("x")) != .scriptFailure("x"))
    }

    @Test("NotesError.errorDescription labels each case")
    func notesErrorLocalizedError() {
        #expect(NotesError.invalidInput("title is required").errorDescription
            == "Invalid input: title is required")
        #expect(NotesError.scriptFailure("parse failed").errorDescription
            == "Notes script failure: parse failed")
    }

    @Test("NotesError.appleScript keeps the runner error's description")
    func notesErrorWrapsAppleScriptDescription() {
        #expect(NotesError.appleScript(.runtime("oops")).errorDescription
            == "AppleScript runtime error: oops")
        #expect(NotesError.appleScript(.compile("nope")).errorDescription
            == "AppleScript compile error: nope")
    }
}
