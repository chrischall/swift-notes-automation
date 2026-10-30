import Foundation
@testable import NotesAutomation
import Testing

/// Pins the typed-throws contract: `NoteStoreReader` only ever throws
/// `NoteStoreReaderError`, every `AppleScriptRunner` (so `NSAppleScriptRunner`
/// too) only ever throws `AppleScriptError`, and every `NoteService` method
/// only ever throws `NotesError`. The `let e: SomeError = error` bindings in these
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

    @Test("the AppleScriptRunner requirement is typed as throws(AppleScriptError)")
    func runnerProtocolSignature() async {
        let fake = FakeAppleScriptRunner()
        fake.queueError("boom")
        let runner: any AppleScriptRunner = fake
        do {
            _ = try await runner.run(source: "x")
            Issue.record("expected run to throw")
        } catch {
            let typed: AppleScriptError = error
            #expect(typed == .runtime("boom"))
        }
    }

    @Test("NoteService throws NotesError without a cast, from every method")
    func serviceMethodsTyped() async {
        let runner = FakeAppleScriptRunner()
        let svc = NoteService(runner: runner)
        for _ in 0 ..< 7 {
            runner.queueError("boom")
        }
        let wrapped = NotesError.appleScript(.runtime("boom"))
        do { _ = try await svc.list() } catch { #expect(Self.typed(error) == wrapped) }
        do { _ = try await svc.search(query: "q") } catch { #expect(Self.typed(error) == wrapped) }
        do { _ = try await svc.get(id: "i") } catch { #expect(Self.typed(error) == wrapped) }
        do { _ = try await svc.folders() } catch { #expect(Self.typed(error) == wrapped) }
        do { _ = try await svc.create(title: "t", body: "b") } catch { #expect(Self.typed(error) == wrapped) }
        do { try await svc.update(id: "i", title: "t") } catch { #expect(Self.typed(error) == wrapped) }
        do { try await svc.delete(id: "i") } catch { #expect(Self.typed(error) == wrapped) }
        #expect(runner.calls.count == 7)
    }

    /// Takes the concrete type, so passing a `catch`-bound `error` only
    /// compiles when the `do` body's thrown type is `NotesError`.
    private static func typed(_ error: NotesError) -> NotesError { error }

    @Test("NoteService validation and parse failures keep their own cases")
    func serviceLocalCases() async {
        let runner = FakeAppleScriptRunner()
        runner.queue("garbage without separators")
        let svc = NoteService(runner: runner)
        await #expect(throws: NotesError.invalidInput("id is required")) {
            try await svc.delete(id: " ")
        }
        await #expect(throws: NotesError.invalidInput("title is required")) {
            _ = try await svc.create(title: "", body: "b")
        }
        do {
            _ = try await svc.get(id: "x-coredata://n/1")
            Issue.record("expected get to throw on unparseable output")
        } catch {
            guard case .scriptFailure = error else {
                Issue.record("expected .scriptFailure, got \(error)")
                return
            }
        }
    }

    @Test("a runner's compile error reaches the caller as .appleScript(.compile)")
    func compileErrorWrapped() async {
        struct CompileFailRunner: AppleScriptRunner {
            func run(source _: String) async throws(AppleScriptError) -> String {
                throw .compile("bad source")
            }
        }
        let svc = NoteService(runner: CompileFailRunner())
        await #expect(throws: NotesError.appleScript(.compile("bad source"))) {
            _ = try await svc.folders()
        }
    }
}
