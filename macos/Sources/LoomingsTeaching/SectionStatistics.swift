import Foundation
import LoomingsMarkdown

/// A heading's section: its range in the source, its words, and its limit.
public struct SectionCount: Equatable, Sendable {
    public let heading: OutlineItem
    /// From the heading line to where the next heading of the same or a
    /// higher level starts (or the end of the document).
    public let range: NSRange
    /// Words in the section, its own heading line not counted.
    public let words: Int
    public let limit: Int?

    public var isOverLimit: Bool { limit.map { words > $0 } ?? false }
}

public enum SectionStatistics {
    public static func sections(_ source: String, outline: [OutlineItem], limits: [SectionLimit]) -> [SectionCount] {
        let text = source as NSString
        let wanted = Dictionary(limits.map { (normalized($0.heading), $0.maxWords) }, uniquingKeysWith: { first, _ in first })
        return outline.enumerated().map { index, heading in
            let start = min(heading.range.location, text.length)
            let next = outline[(index + 1)...].first { $0.level <= heading.level }
            let end = min(next?.range.location ?? text.length, text.length)
            let bodyStart = min(end, endOfHeading(at: start, in: text))
            let body = text.substring(with: NSRange(location: bodyStart, length: max(0, end - bodyStart)))
            return SectionCount(
                heading: heading,
                range: NSRange(location: start, length: max(0, end - start)),
                words: TextStatistics.countWords(body),
                limit: wanted[normalized(heading.title)]
            )
        }
    }

    /// Just past the heading's line, and past a setext underline when there is one.
    private static func endOfHeading(at location: Int, in text: NSString) -> Int {
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        var end = NSMaxRange(line)
        guard end < text.length else { return end }
        let next = text.lineRange(for: NSRange(location: end, length: 0))
        let underline = text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("#"),
           !underline.isEmpty, underline.allSatisfy({ $0 == "=" }) || underline.allSatisfy({ $0 == "-" }) {
            end = NSMaxRange(next)
        }
        return end
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
