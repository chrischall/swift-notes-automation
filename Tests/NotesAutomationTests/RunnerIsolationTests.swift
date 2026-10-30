import Foundation
import NotesAutomation
import Testing

/// Pins where `AppleScriptRunner` work executes under
/// `NonisolatedNonsendingByDefault`.
///
/// With that feature a nonisolated `async` function runs on its caller's
/// actor. A consumer's runner may block — shelling out to `osascript`,
/// say — so the protocol requirement is `@concurrent`: however the
/// conformer is written, a call through the protocol leaves the caller's
/// actor, as every nonisolated `async` call did before the feature.
@Suite("AppleScriptRunner isolation")
struct RunnerIsolationTests {
    /// Answers every script with whether it ran on the main thread.
    /// Its `run` is nonisolated(nonsending) under this target's settings.
    struct ThreadProbeRunner: AppleScriptRunner {
        func run(source _: String) async throws -> String {
            Self.onMain() ? "main" : "background"
        }

        private static func onMain() -> Bool { Thread.isMainThread }
    }

    @Test("a runner called from the main actor runs off the main thread")
    @MainActor
    func runnerLeavesMainActor() async throws {
        let runner: any AppleScriptRunner = ThreadProbeRunner()
        #expect(try await runner.run(source: "") == "background")
    }

    @Test("NoteService on the main actor still runs its runner off the main thread")
    @MainActor
    func serviceRunnerLeavesMainActor() async throws {
        let service = NoteService(runner: ThreadProbeRunner())
        #expect(try await service.folders() == ["background"])
    }
}
