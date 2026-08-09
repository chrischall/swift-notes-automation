import Foundation

#if canImport(OSAKit)
import OSAKit
#endif

/// Production ``AppleScriptRunner`` backed by `NSAppleScript`.
///
/// Each call to ``run(source:)`` constructs and executes its own
/// `NSAppleScript` on the **main thread**, via ``onMainThread(_:)``.
///
/// ## Why the main thread is mandatory
///
/// A script that targets another application — every script this package
/// emits begins `tell application "Notes"` — sends an Apple Event and
/// blocks awaiting the reply. AppleScript waits inside Carbon's
/// `AEDefaultActiveProc`, which pumps for the reply with
/// `GetNextEventMatchingMask`. That call services only the **main**
/// thread's event queue, and the Apple Event reply is delivered there.
///
/// Run the script on any other thread and the reply lands on the main
/// queue with nobody waiting on it while the executing thread blocks in
/// `mach_msg` — forever. It is a permanent hang, not a slow call: no
/// timeout fires and no error is raised.
///
/// This bites only cross-application scripts. Self-contained ones
/// (`return "hello"`) send no Apple Event and complete from any thread,
/// which is what makes the bug so easy to miss in tests.
///
/// ## Consequences for callers
///
/// ``run(source:)`` occupies the main actor for the script's duration,
/// so AppleScript calls serialize. That is the correct behaviour anyway:
/// `NSAppleScript` is neither `Sendable` nor reentrant, and concurrent
/// events to a single app are serialized by that app regardless.
///
/// Using `NSAppleScript` rather than shelling out to `osascript` avoids
/// the per-call subprocess cost and the shell-escaping hazards that come
/// with building a command line from untrusted strings.
public struct NSAppleScriptRunner: AppleScriptRunner {
    /// Creates a runner.
    ///
    /// There is no per-instance configuration — all state lives in the
    /// per-call `NSAppleScript` object.
    public init() {}

    /// Hops to the main thread and runs `body` there.
    ///
    /// The single seam through which every `NSAppleScript` invocation
    /// passes, so the main-thread invariant documented above is
    /// established in exactly one place — and can be asserted by tests
    /// without needing Notes.app or an Automation permission grant.
    static func onMainThread<T: Sendable>(
        _ body: @MainActor @Sendable () throws -> T
    ) async rethrows -> T {
        try await MainActor.run(body: body)
    }

    /// Compiles and executes `source`, returning the scalar result as a
    /// `String`.
    ///
    /// - Parameter source: AppleScript source code.
    /// - Returns: `descriptor.stringValue` of the final descriptor, or
    ///   `""` when the result cannot be coerced to a string.
    /// - Throws: ``AppleScriptError/compile(_:)`` when the source cannot
    ///   be constructed; ``AppleScriptError/runtime(_:)`` when
    ///   AppleScript reports an error at execution time.
    public func run(source: String) async throws -> String {
        // Constructed *and* executed inside the hop: `NSAppleScript` is
        // not `Sendable`, so its whole lifetime stays on one thread.
        try await Self.onMainThread { () throws -> String in
            guard let script = NSAppleScript(source: source) else {
                throw AppleScriptError.compile("Failed to construct NSAppleScript")
            }
            var errorInfo: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String
                    ?? errorInfo[NSAppleScript.errorBriefMessage] as? String
                    ?? "AppleScript error \(errorInfo[NSAppleScript.errorNumber] ?? "?")"
                throw AppleScriptError.runtime(message)
            }
            return descriptor.stringValue ?? ""
        }
    }
}
