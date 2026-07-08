import Foundation
import Testing
@testable import NotesAutomation

/// Security regression tests: every value interpolated into an AppleScript
/// string literal must have BOTH backslashes and double-quotes escaped, in
/// that order (`\` → `\\` first, then `"` → `\"`). Escaping only quotes lets
/// input containing `\"` or a trailing `\` terminate the literal early and
/// smuggle the remainder in as AppleScript — an injection that reaches
/// `do shell script`.
@Suite("AppleScript escaping (injection defense)")
struct AppleScriptEscapingTests {
    /// An id/title/query crafted to break out of a quote-only-escaped literal
    /// and run a shell command. Contains a literal backslash-then-quote.
    static let injection = #"foo\" & (do shell script "id") & ""#

    // MARK: - escapeForAppleScript helper

    @Test("escapeForAppleScript doubles backslashes before escaping quotes")
    func helperOrder() {
        // A lone backslash must become two backslashes.
        #expect(NoteService.escapeForAppleScript(#"\"#) == #"\\"#)
        // A lone quote must become backslash-quote.
        #expect(NoteService.escapeForAppleScript("\"") == #"\""#)
        // A literal `\"` (backslash then quote) must become `\\\"` — NOT `\\"`
        // (which a naive quote-only escape, or a wrong-order escape, produces).
        #expect(NoteService.escapeForAppleScript(#"\""#) == #"\\\""#)
    }

    @Test("escapeForAppleScript escapes a trailing backslash so it can't eat the closing quote")
    func helperTrailingBackslash() {
        #expect(NoteService.escapeForAppleScript(#"abc\"#) == #"abc\\"#)
    }

    // MARK: - deleteScript

    @Test("deleteScript escapes backslashes in the id (injection payload stays inside the literal)")
    func deleteScriptEscapesBackslash() {
        let script = NoteService.deleteScript(id: Self.injection)
        // The literal `\"` in the payload must appear as `\\\"` in the source.
        #expect(script.contains(#"foo\\\""#))
        // And there must be no bare `foo\"` (backslash-quote) that would close
        // the AppleScript string literal early.
        #expect(!script.contains(#"foo\""# + " "))
    }

    @Test("deleteScript escapes a trailing backslash in the id")
    func deleteScriptTrailingBackslash() {
        let script = NoteService.deleteScript(id: #"x-coredata://notes/42\"#)
        #expect(script.contains(#"notes/42\\"#))
    }

    // MARK: - listOrSearchScript

    @Test("listOrSearchScript escapes backslashes in the search query")
    func searchScriptEscapesBackslash() {
        let script = NoteService.listOrSearchScript(query: Self.injection, limit: 10)
        #expect(script.contains(#"foo\\\""#))
    }

    // MARK: - create

    @Test("create escapes backslashes in the title")
    func createEscapesTitleBackslash() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id")
        let svc = NoteService(runner: runner)

        _ = try await svc.create(title: Self.injection, body: "")

        let src = runner.calls[0]
        #expect(src.contains(#"foo\\\""#))
    }

    @Test("create escapes backslashes in the body")
    func createEscapesBodyBackslash() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id")
        let svc = NoteService(runner: runner)

        _ = try await svc.create(title: "ok", body: Self.injection)

        let src = runner.calls[0]
        #expect(src.contains(#"foo\\\""#))
    }

    @Test("create escapes backslashes in the folder name")
    func createEscapesFolderBackslash() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id")
        let svc = NoteService(runner: runner)

        _ = try await svc.create(title: "ok", body: "", folder: Self.injection)

        let src = runner.calls[0]
        #expect(src.contains(#"foo\\\""#))
    }

    @Test("create escapes a trailing backslash in the body without closing the literal")
    func createTrailingBackslashBody() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("id")
        let svc = NoteService(runner: runner)

        _ = try await svc.create(title: "ok", body: #"ends in a backslash\"#)

        let src = runner.calls[0]
        #expect(src.contains(#"backslash\\"#))
    }
}
