import Foundation

extension String {
    /// Returns `self` when it is non-empty, otherwise `nil`.
    ///
    /// Useful for precedence chains with the nil-coalescing operator —
    /// for example, when collapsing an explicit value, an environment
    /// fallback, and an error in order:
    ///
    /// ```swift
    /// let folder = explicitFolder.nonEmpty
    ///     ?? ProcessInfo.processInfo.environment["FOLDER"]
    ///     ?? "Notes"
    /// ```
    ///
    /// Note that "non-empty" uses `String.isEmpty`, so a string of just
    /// whitespace is still considered non-empty.
    public var nonEmpty: String? { isEmpty ? nil : self }
}
