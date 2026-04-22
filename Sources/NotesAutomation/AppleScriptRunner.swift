import Foundation

/// A type that can execute AppleScript source and return its scalar result.
///
/// The protocol exists so service code that drives Notes, Mail, Messages,
/// or any other AppleScript-scriptable application can be unit-tested
/// without invoking the real system bridge. Production callers use
/// ``NSAppleScriptRunner``; tests inject a fake that returns canned
/// responses.
///
/// Conforming types must be `Sendable` so a single runner can be shared
/// across concurrent service calls.
public protocol AppleScriptRunner: Sendable {
    /// Executes `source` and returns the scalar result as a string.
    ///
    /// - Parameter source: Complete, unescaped AppleScript source code.
    ///   The runner handles compilation.
    /// - Returns: The result of the final AppleScript expression, coerced
    ///   to `String`. Returns `""` when the script produces no string
    ///   result.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when AppleScript
    ///   reports an error at execution time — for example, the target
    ///   application is not running, Automation permission is denied, or
    ///   the script executes an `error "…"` statement.
    ///   ``AppleScriptError/compile(_:)`` when `source` cannot be
    ///   compiled into an executable script.
    func run(source: String) async throws -> String
}

/// Errors surfaced by an ``AppleScriptRunner`` execution.
///
/// The two cases mirror the two failure modes of `NSAppleScript`: an
/// error at construction time (compile) and an error at execution time
/// (runtime). In practice nearly all failures are `runtime` — Apple's
/// script compiler is permissive and defers most parsing until execution.
public enum AppleScriptError: Error, Equatable, Sendable {
    /// The script compiled but AppleScript signaled an error during
    /// execution.
    ///
    /// The associated value is the message from
    /// `NSAppleScriptErrorMessage` — falling back to
    /// `NSAppleScriptErrorBriefMessage` or the numeric error code when
    /// the primary key is missing.
    case runtime(String)

    /// The script source could not be compiled into an `NSAppleScript`
    /// instance.
    ///
    /// Extremely rare in practice; `NSAppleScript`'s initializer is very
    /// permissive about what it accepts.
    case compile(String)
}

extension AppleScriptError: LocalizedError {
    /// Human-readable description suitable for logs and user display.
    public var errorDescription: String? {
        switch self {
        case .runtime(let message):
            return "AppleScript runtime error: \(message)"
        case .compile(let message):
            return "AppleScript compile error: \(message)"
        }
    }
}
