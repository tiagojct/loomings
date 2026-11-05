import Foundation

/// Links the formatted text to the editor's text, which differ in length. Each
/// source line stays at its number in the formatted text (`replaceRanges` in
/// `src/citations/output.js`), and the reference list comes after the last one.
public struct CitationLineMap: Sendable {
    private let sourceStarts: [Int]
    private let sourceLength: Int
    private let markdownStarts: [Int]
    private let markdownLength: Int

    public init(source: String, markdown: String) {
        (sourceStarts, sourceLength) = Self.lineStarts(of: source)
        (markdownStarts, markdownLength) = Self.lineStarts(of: markdown)
    }

    /// The same column of the same line, kept inside the line.
    public func markdownLocation(forSource location: Int) -> Int {
        let line = Self.line(of: location, in: sourceStarts)
        guard line < markdownStarts.count else { return markdownLength }
        let next = line + 1 < markdownStarts.count ? markdownStarts[line + 1] - 1 : markdownLength
        return min(markdownStarts[line] + location - sourceStarts[line], next)
    }

    /// The whole source lines of a block. Nil for a block after the source.
    public func sourceRange(forMarkdown range: NSRange) -> NSRange? {
        let first = Self.line(of: range.location, in: markdownStarts)
        guard first < sourceStarts.count else { return nil }
        let last = min(
            Self.line(of: max(range.location, NSMaxRange(range) - 1), in: markdownStarts),
            sourceStarts.count - 1
        )
        let end = last + 1 < sourceStarts.count ? sourceStarts[last + 1] - 1 : sourceLength
        return NSRange(location: sourceStarts[first], length: end - sourceStarts[first])
    }

    private static func lineStarts(of text: String) -> (starts: [Int], length: Int) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 { starts.append(offset) }
        }
        return (starts, offset)
    }

    /// The index of the last start at or before `offset`.
    private static func line(of offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
