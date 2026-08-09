import Foundation
import Testing
@testable import NotesAutomation

/// Live tests for `NSAppleScriptRunner` that exercise the real
/// `NSAppleScript` bridge.
///
/// **Opt-in**: set `NOTES_AUTOMATION_INTEGRATION=1` in the environment
/// to run. Without the env var every test in this suite is skipped.
///
/// ```bash
/// NOTES_AUTOMATION_INTEGRATION=1 swift test
/// ```
///
/// Why opt-in: Apple's AppleScript bridge behaves unpredictably when
/// invoked from inside an `xctest` test bundle on recent macOS versions
/// (trivial scripts intermittently fail with error `-1751` / "event not
/// handled"). The bridge works reliably from shipped binaries, which is
/// what the library's consumers use. The integration suite already gates
/// its real-Notes tests on the same env var, so opting into one gets you
/// the other.
///
/// The suite is serialized — `NSAppleScript` is not reentrant, so
/// parallel invocations from the same process can race.
@Suite("NSAppleScriptRunner", .serialized)
struct NSAppleScriptRunnerTests {
    private static let enabled = ProcessInfo.processInfo
        .environment["NOTES_AUTOMATION_INTEGRATION"] == "1"
    private static let enabledComment: Comment =
        "set NOTES_AUTOMATION_INTEGRATION=1 to exercise the real NSAppleScript bridge"

    @Test("run returns the scalar result of a successful script",
          .disabled(if: !enabled, enabledComment))
    func returnsScalar() async throws {
        let runner = NSAppleScriptRunner()
        let result = try await runner.run(source: "return \"hello\"")
        #expect(result == "hello")
    }

    @Test("run coerces non-string results via descriptor.stringValue",
          .disabled(if: !enabled, enabledComment))
    func returnsCoercibleScalar() async throws {
        let runner = NSAppleScriptRunner()
        let result = try await runner.run(source: "return 1 + 1")
        #expect(result == "2")
    }

    /// The regression test for the off-main-thread stall.
    ///
    /// Unlike the scalar tests above this script targets *another
    /// application*, so it sends a real Apple Event and waits for the
    /// reply — the shape that stalls when `NSAppleScript` runs off the
    /// main thread.
    ///
    /// The assertion is on **latency**, not just completion: run off the
    /// main thread this same script was measured at ~32s (and, inside a
    /// long-lived server process, still unreturned after ten minutes),
    /// against ~0.1s on the main thread. A bound of 5s sits ~50x above
    /// the healthy time and well under the broken one, so it discriminates
    /// without being flaky. A first warm-up call absorbs Notes.app launch.
    @Test("a cross-application script completes without stalling",
          .disabled(if: !enabled, enabledComment),
          .timeLimit(.minutes(1)))
    func crossApplicationScriptCompletes() async throws {
        let runner = NSAppleScriptRunner()
        let source = "tell application \"Notes\" to return (count of folders) as string"

        _ = try await runner.run(source: source)  // warm-up: launch + first AE

        let started = ContinuousClock.now
        let result = try await runner.run(source: source)
        let elapsed = ContinuousClock.now - started

        #expect(Int(result) != nil, "expected a folder count, got \(result)")
        #expect(
            elapsed < .seconds(5),
            """
            a warm cross-application Apple Event took \(elapsed) — that is the             signature of NSAppleScript executing off the main thread, where the             reply is not serviced by the main run loop.
            """
        )
    }

    @Test("run throws AppleScriptError.runtime when the script raises",
          .disabled(if: !enabled, enabledComment))
    func runtimeErrorIsThrown() async throws {
        let runner = NSAppleScriptRunner()
        await #expect(throws: AppleScriptError.self) {
            _ = try await runner.run(source: "error \"oops\"")
        }
    }

    @Test("runtime error message propagates the script's error text",
          .disabled(if: !enabled, enabledComment))
    func runtimeErrorMessagePropagates() async throws {
        let runner = NSAppleScriptRunner()
        let distinctive = "NSAppleScriptRunnerTests_distinct_12345"
        do {
            _ = try await runner.run(source: "error \"\(distinctive)\"")
            Issue.record("expected the script to throw")
        } catch let error as AppleScriptError {
            guard case .runtime(let message) = error else {
                Issue.record("expected .runtime, got \(error)")
                return
            }
            #expect(message.contains(distinctive))
        }
    }
}

/// Thread-affinity tests for `NSAppleScriptRunner`.
///
/// These are **not** opt-in: they need neither Notes.app nor an
/// Automation TCC grant, so they guard the invariant everywhere the
/// package is built.
///
/// The invariant: `NSAppleScript` must execute on the **main thread**.
/// When a script targets another application (`tell application "Notes"
/// …`), AppleScript sends an Apple Event and waits for the reply via
/// Carbon's `AEDefaultActiveProc` → `GetNextEventMatchingMask`, which
/// only pumps the *main* thread's event queue. Executed on any other
/// thread the reply is never dispatched and the call blocks in
/// `mach_msg` forever — a permanent hang, not a slow call.
///
/// Trivial scripts (`return "hello"`) send no Apple Event and so pass
/// from any thread, which is why the opt-in suite above never caught
/// this.
@Suite("NSAppleScriptRunner thread affinity")
struct NSAppleScriptRunnerThreadAffinityTests {
    @Test("script execution is confined to the main thread")
    func executesOnMainThread() async {
        let ranOnMain = await NSAppleScriptRunner.onMainThread { Thread.isMainThread }
        #expect(
            ranOnMain,
            """
            NSAppleScript must execute on the main thread — Apple Event \
            replies are delivered to the main run loop, so running it on a \
            background thread hangs forever on any `tell application` script.
            """
        )
    }

    @Test("the result of the main-thread hop reaches the caller")
    func propagatesResult() async {
        let value = await NSAppleScriptRunner.onMainThread { 6 * 7 }
        #expect(value == 42)
    }

    @Test("errors thrown on the main thread propagate to the caller")
    func propagatesThrow() async {
        await #expect(throws: AppleScriptError.self) {
            try await NSAppleScriptRunner.onMainThread {
                throw AppleScriptError.compile("boom")
            }
        }
    }
}
