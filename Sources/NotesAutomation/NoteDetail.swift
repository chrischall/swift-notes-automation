import Foundation

/// A note's full contents, returned from ``NoteService/get(id:)``.
///
/// Where ``Note`` carries only a truncated ``Note/snippet`` for scannable
/// list/search results, `NoteDetail` carries the note's **complete,
/// untruncated body** in two forms — ``plainText`` and ``html`` — plus
/// creation and modification dates. Use it when you need the whole note,
/// not just a preview.
///
/// Like ``Note``, this is a pure value type decoupled from Notes.app's
/// underlying Core Data model, so consumers and tests never touch
/// AppleScript objects directly.
public struct NoteDetail: Equatable, Hashable, Identifiable, Sendable {
    /// Opaque Notes.app identifier — the same id format returned by
    /// ``Note/id`` and ``NoteService/create(title:body:folder:)``.
    public let id: String

    /// The note's title (Notes.app's `name of note`).
    public let title: String

    /// Name of the note's containing folder, or `""` when unfiled.
    public let folder: String

    /// The note's complete body as plain text, with all formatting
    /// stripped. Newlines and tabs are preserved. Never truncated.
    public let plainText: String

    /// The note's complete body as Notes.app HTML (`body of note`).
    /// Preserves rich structure — headings, lists, links. Never truncated.
    public let html: String

    /// When the note was created, or `nil` when Notes.app didn't report a
    /// parseable date.
    public let creationDate: Date?

    /// When the note was last modified, or `nil` when Notes.app didn't
    /// report a parseable date.
    public let modificationDate: Date?

    /// Creates a `NoteDetail` with the given fields.
    public init(
        id: String,
        title: String,
        folder: String,
        plainText: String,
        html: String,
        creationDate: Date?,
        modificationDate: Date?
    ) {
        self.id = id
        self.title = title
        self.folder = folder
        self.plainText = plainText
        self.html = html
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}
