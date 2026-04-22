import Foundation
import Testing
@testable import NotesAutomation

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

    // MARK: - NoteServiceError

    @Test("NoteServiceError equality discriminates cases and associated values")
    func noteServiceEquatable() {
        #expect(NoteServiceError.invalidInput("x") == .invalidInput("x"))
        #expect(NoteServiceError.invalidInput("x") != .invalidInput("y"))
        #expect(NoteServiceError.scriptFailure("x") == .scriptFailure("x"))
        #expect(NoteServiceError.scriptFailure("x") != .invalidInput("x"))
    }

    @Test("NoteServiceError.errorDescription labels each case")
    func noteServiceLocalizedError() {
        #expect(NoteServiceError.invalidInput("title is required").errorDescription
                == "Invalid input: title is required")
        #expect(NoteServiceError.scriptFailure("parse failed").errorDescription
                == "Notes script failure: parse failed")
    }
}
