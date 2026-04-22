import Foundation

/// A note returned from ``NoteService``.
///
/// `Note` is a pure value type, decoupled from Notes.app's underlying
/// Core Data model so that consumers and tests never touch AppleScript
/// objects directly. The service layer projects Notes.app state into this
/// type.
///
/// The conformances (`Equatable`, `Hashable`, `Identifiable`, `Sendable`)
/// let `Note` interoperate naturally with SwiftUI lists, `Set`, dictionary
/// keys, and concurrent code.
public struct Note: Equatable, Hashable, Identifiable, Sendable {
    /// Opaque Notes.app identifier.
    ///
    /// Stable for the life of the note; pass it back to future APIs that
    /// need to reference this note. Callers should treat the string as
    /// opaque — it's currently a Core Data `x-coredata://…` URI, but that
    /// is not part of the contract.
    public let id: String

    /// The note's title.
    ///
    /// Mapped from AppleScript's `name of note`. Corresponds to the text
    /// that appears at the top of the note and in Notes.app's sidebar.
    public let title: String

    /// First ~200 characters of the note's body, tab- and newline-stripped.
    ///
    /// Empty when the body could not be read (for example, a locked note).
    /// Use ``title`` as a fallback for display when this is empty.
    public let snippet: String

    /// Name of the note's containing folder.
    ///
    /// For example, `"Notes"`, `"Recipes"`, or `"Work"`. Empty when the
    /// note is not in any folder, which is rare — Notes typically places
    /// loose notes in the default account's `"Notes"` folder.
    public let folder: String

    /// Creates a `Note` with the given fields.
    ///
    /// - Parameters:
    ///   - id: Opaque Notes.app identifier.
    ///   - title: Note title.
    ///   - snippet: First ~200 characters of the body, whitespace-normalized.
    ///   - folder: Containing folder name, or `""` if unfiled.
    public init(id: String, title: String, snippet: String, folder: String) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.folder = folder
    }
}
