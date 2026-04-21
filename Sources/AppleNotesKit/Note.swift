import Foundation

public struct Note: Equatable, Sendable {
    public let id: String
    public let title: String
    public let snippet: String    // first N chars of body for list/search results
    public let folder: String

    public init(id: String, title: String, snippet: String, folder: String) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.folder = folder
    }
}
