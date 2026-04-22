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
