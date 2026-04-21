import Foundation

/// A note returned from `NoteService`. Decoupled from Notes.app's
/// underlying Core Data model — pure value type so consumers and tests
/// never touch AppleScript objects.
public struct Note: Equatable, Sendable {
    /// Opaque Notes.app identifier. Stable for the life of the note;
    /// pass back to future APIs that need to reference it.
    public let id: String

    /// Note title — the text that appears in Notes.app's sidebar / first
    /// line. Mapped to AppleScript's `name of note`.
    public let title: String

    /// First ~200 characters of the note body, tab/newline-stripped.
    /// Empty when content couldn't be read (e.g. locked note).
    public let snippet: String

    /// Containing folder name, e.g. `"Notes"`, `"Recipes"`, `"Work"`.
    /// Empty string when the note isn't in a folder (rare).
    public let folder: String

    public init(id: String, title: String, snippet: String, folder: String) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.folder = folder
    }
}
