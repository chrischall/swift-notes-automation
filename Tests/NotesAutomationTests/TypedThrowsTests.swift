import Foundation
@testable import NotesAutomation
import Testing

/// Pins the typed-throws contract: `NoteStoreReader` only ever throws
/// `NoteStoreReaderError`, and `NSAppleScriptRunner` only ever throws
/// `AppleScriptError`. The `let e: SomeError = error` bindings in these
/// `catch` blocks only compile when the call site's thrown type is the
/// concrete error type, so a regression to untyped `throws` fails the
/// build, not just a test.
@Suite("Typed throws")
struct TypedThrowsTests {
    @Test("NoteStoreReader.init throws NoteStoreReaderError without a cast")
    func readerInit() {
        do {
            _ = try NoteStoreReader(path: "/nonexistent/\(UUID().uuidString)/NoteStore.sqlite")
            Issue.record("expected init to throw")
        } catch {
            let typed: NoteStoreReaderError = error
            guard case .databaseNotAccessible = typed else {
                Issue.record("unexpected error \(typed)")
                return
            }
        }
    }

    @Test("NoteStoreReader queries throw NoteStoreReaderError without a cast")
    func readerQueries() async throws {
        let path = try NoteStoreFixture.create()
        let reader = try NoteStoreReader(path: path)
        // Remove the store after init so every query's fresh open fails.
        try FileManager.default.removeItem(atPath: path)
        do {
            _ = try await reader.list()
            Issue.record("expected list to throw once the store is gone")
        } catch {
            #expect(Self.isNotAccessible(error))
        }
        do {
            _ = try await reader.search(query: "x")
            Issue.record("expected search to throw once the store is gone")
        } catch {
            #expect(Self.isNotAccessible(error))
        }
        do {
            _ = try await reader.folders()
            Issue.record("expected folders to throw once the store is gone")
        } catch {
            #expect(Self.isNotAccessible(error))
        }
    }

    /// Takes the concrete type, so passing a `catch`-bound `error` only
    /// compiles when the `do` body's thrown type is `NoteStoreReaderError`.
    private static func isNotAccessible(_ error: NoteStoreReaderError) -> Bool {
        if case .databaseNotAccessible = error {
            return true
        }
        return false
    }

    @Test("NSAppleScriptRunner.run is typed as throws(AppleScriptError)")
    func runnerRunSignature() {
        /// Compile-time check only — never reaches the AppleScript bridge.
        func requireTyped(
            _: (String) async throws(AppleScriptError) -> String
        ) {}
        requireTyped(NSAppleScriptRunner().run(source:))
    }

    @Test("NSAppleScriptRunner.onMainThread preserves the closure's error type")
    func onMainThreadTyped() async {
        do {
            try await NSAppleScriptRunner.onMainThread { () throws(AppleScriptError) in
                throw AppleScriptError.compile("boom")
            }
        } catch {
            let typed: AppleScriptError = error
            #expect(typed == .compile("boom"))
        }
    }
}
