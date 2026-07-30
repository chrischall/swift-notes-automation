import Foundation

/// One `offset`/`maxChars` window into a note body, produced by
/// ``NoteService/bodyPage(_:offset:maxChars:)``.
///
/// Positions are counted in `Character`s (grapheme clusters), so emoji and
/// combining sequences never split. `start`/`end` are clamped to the body;
/// `text` is always a valid slice. Callers that need to distinguish "empty
/// final page" from "offset past the end" should compare their *requested*
/// offset against ``total``.
///
/// The type exists so consumers paging a long ``NoteDetail/plainText`` can
/// report truncation honestly: everything needed for a "showing X–Y of Z,
/// N omitted, continue at offset O" message is here.
public struct NoteBodyPage: Equatable, Hashable, Sendable {
    /// The windowed slice of the body.
    public let text: String

    /// Index of the first character in ``text``, clamped to the body length.
    public let start: Int

    /// Index one past the last character in ``text`` — the `offset` to pass
    /// for the next page.
    public let end: Int

    /// The full body's character count.
    public let total: Int

    /// Creates a page. Consumers normally get one from
    /// ``NoteService/bodyPage(_:offset:maxChars:)`` rather than building
    /// their own.
    public init(text: String, start: Int, end: Int, total: Int) {
        self.text = text
        self.start = start
        self.end = end
        self.total = total
    }

    /// True when any part of the body falls outside this window.
    public var isTruncated: Bool { start > 0 || end < total }

    /// Characters of the body not included in this window.
    public var omitted: Int { total - (end - start) }
}
