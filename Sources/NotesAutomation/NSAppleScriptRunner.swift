import Foundation

#if canImport(OSAKit)
import OSAKit
#endif

/// Production ``AppleScriptRunner`` backed by `NSAppleScript`.
///
/// Each call to ``run(source:)`` constructs and executes its own
/// `NSAppleScript` inside a `Task.detached`. `NSAppleScript` is not
/// `Sendable`, so confining its lifetime to a single cooperative task
/// keeps the library safe under Swift 6 strict concurrency and sidesteps
/// Foundation's thread-affinity concerns.
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
        try await Task.detached(priority: .userInitiated) { () throws -> String in
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
        }.value
    }
}
