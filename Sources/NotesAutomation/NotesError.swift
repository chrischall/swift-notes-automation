public import Foundation

/// The one error type every ``NoteService`` method throws.
///
/// Each method is declared `throws(NotesError)`, so a `catch` block binds
/// `error` as a `NotesError` — no `as?` casts — and an exhaustive `switch`
/// covers every failure:
///
/// ```swift
/// do {
///     let note = try await notes.get(id: id)
/// } catch {
///     switch error {
///     case let .invalidInput(what):
///         // rejected before any AppleScript ran
///     case let .scriptFailure(why):
///         // the script ran, but its output didn't parse
///     case let .appleScript(.runtime(message)):
///         // Notes.app not running, Automation denied, no note with that id, …
///     case let .appleScript(.compile(message)):
///         // the runner couldn't compile the script
///     }
/// }
/// ```
///
/// (Swift doesn't check a chain of pattern `catch` clauses for
/// exhaustiveness, so a `switch` inside one `catch` is the way to cover
/// every case without a fallback.)
///
/// Replaces `NoteServiceError` (same two leading cases) and absorbs the
/// runner's ``AppleScriptError``, which used to escape `NoteService`
/// untyped. ``NoteStoreReader`` keeps its own ``NoteStoreReaderError``.
public enum NotesError: Error, Equatable, Sendable {
    /// The caller passed an empty or whitespace-only string for a
    /// required parameter (most commonly `title` on
    /// ``NoteService/create(title:body:folder:)``), or an update with
    /// nothing to change. No AppleScript ran.
    ///
    /// The associated value names the offending parameter.
    case invalidInput(String)

    /// AppleScript ran successfully but Notes.app reported a non-success
    /// result, or the returned payload could not be parsed.
    ///
    /// The associated value carries a human-readable diagnostic intended
    /// for logs, not end users.
    case scriptFailure(String)

    /// The ``AppleScriptRunner`` failed: `.runtime` when Notes.app is not
    /// running, Automation permission is denied, or no note has the given
    /// id; `.compile` when the script could not be compiled.
    case appleScript(AppleScriptError)
}

extension NotesError: LocalizedError {
    /// Human-readable description suitable for logs and user display.
    ///
    /// `.appleScript` forwards the wrapped ``AppleScriptError``'s
    /// description, so messages read exactly as they did before the
    /// runner's error was wrapped.
    public var errorDescription: String? {
        switch self {
        case let .invalidInput(message):
            "Invalid input: \(message)"
        case let .scriptFailure(message):
            "Notes script failure: \(message)"
        case let .appleScript(error):
            error.errorDescription
        }
    }
}

/// The pre-3.0 name for ``NotesError``.
///
/// Its two cases carry over unchanged, so code that only constructs or
/// matches `.invalidInput` / `.scriptFailure` keeps compiling with a
/// rename warning. Runner failures, which used to surface as a bare
/// ``AppleScriptError``, now arrive as ``NotesError/appleScript(_:)``.
@available(*, deprecated, renamed: "NotesError")
public typealias NoteServiceError = NotesError
