import Foundation

/// One entry of the bibliography, as the completion list shows it.
public struct CitationCompletion: Equatable, Sendable {
    public let key: String
    public let authors: String
    public let year: String
    public let title: String

    public init(key: String, authors: String, year: String, title: String) {
        self.key = key
        self.authors = authors
        self.year = year
        self.title = title
    }

    /// The row in the list. The list holds plain text, so the row is also
    /// the way back to the key.
    public var row: String {
        let detail = [authors, year].filter { !$0.isEmpty }.joined(separator: " ")
        return detail.isEmpty ? key : "\(key)  \(detail)"
    }

    private static let longestQuery = 40
    private static let mostRows = 100

    /// The sign and the query that end at `caret`. The rule is the rule of
    /// `citationCompletions` in `src/citations/editor.js`. Before the sign,
    /// a letter means an email address and a backslash means an escaped sign.
    public static func queryRange(in text: NSString, caret: Int) -> NSRange? {
        guard caret <= text.length else { return nil }
        var index = caret
        let first = max(0, caret - longestQuery - 1)
        while index > first {
            index -= 1
            switch text.character(at: index) {
            case 0x40:
                if index > 0, isKeyCharacter(text.character(at: index - 1)) { return nil }
                return NSRange(location: index, length: caret - index)
            case 0x5B, 0x5D, 0x3B, 0x0A, 0x0D:
                return nil
            default:
                break
            }
        }
        return nil
    }

    private static func isKeyCharacter(_ unit: unichar) -> Bool {
        if unit == 0x5F || unit == 0x5C { return true }
        guard let scalar = UnicodeScalar(unit) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    /// The entries that have each word of `query` in the key, the authors or
    /// the title. This is matching in the interface, not a citation rule.
    public static func matches(_ query: String, in entries: [CitationCompletion]) -> [CitationCompletion] {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        var found: [CitationCompletion] = []
        for entry in entries {
            let text = fold("\(entry.key) \(entry.authors) \(entry.title)")
            guard words.allSatisfy({ text.contains($0) }) else { continue }
            found.append(entry)
            if found.count == mostRows { break }
        }
        return found
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// A citation in the text. It follows the edits until the next report.
public struct CitationMark: Equatable, Sendable {
    public let range: NSRange
    public let isUnknown: Bool

    public init(range: NSRange, isUnknown: Bool) {
        self.range = range
        self.isUnknown = isUnknown
    }
}

/// One replacement in a text, in UTF-16 units.
public struct TextChange: Equatable, Sendable {
    /// The replaced text, in the old text.
    public let range: NSRange
    public let newLength: Int

    public init(range: NSRange, newLength: Int) {
        self.range = range
        self.newLength = newLength
    }

    /// The one change that covers each difference, or nil for equal texts.
    /// The change does not start or end in a surrogate pair.
    public static func between(_ old: String, _ new: String) -> TextChange? {
        let before = Array(old.utf16)
        let after = Array(new.utf16)
        let limit = min(before.count, after.count)
        var head = 0
        while head < limit, before[head] == after[head] { head += 1 }
        if head == before.count, head == after.count { return nil }
        if head > 0, UTF16.isLeadSurrogate(before[head - 1]) { head -= 1 }
        var tail = 0
        while tail < limit - head, before[before.count - 1 - tail] == after[after.count - 1 - tail] { tail += 1 }
        if tail > 0, UTF16.isTrailSurrogate(before[before.count - tail]) { tail -= 1 }
        return TextChange(
            range: NSRange(location: head, length: before.count - head - tail),
            newLength: after.count - head - tail
        )
    }

    /// `range` in the new text, or nil when the change touches it. An
    /// insertion at either end of `range` does not touch it.
    public func map(_ mapped: NSRange) -> NSRange? {
        if NSMaxRange(mapped) <= range.location { return mapped }
        guard mapped.location >= NSMaxRange(range) else { return nil }
        return NSRange(location: mapped.location + newLength - range.length, length: mapped.length)
    }

    /// The text that took the place of `range`.
    public func replacement(in new: String) -> String {
        (new as NSString).substring(with: NSRange(location: range.location, length: newLength))
    }
}
