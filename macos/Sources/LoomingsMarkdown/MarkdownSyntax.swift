import Foundation

/// A syntactic element the editor dims or colours. The kinds stay close to
/// what is visible in the source; the preview and outline do not use them.
public enum MarkdownSyntaxKind: String, Sendable, Equatable, Hashable {
    case headingMarker
    case emphasisMarker
    case strongMarker
    case strikethroughMarker
    case inlineCodeMarker
    case fencedCodeDelimiter
    case codeBlockContent
    case blockQuoteMarker
    case listMarker
    case linkPunctuation
    case imagePunctuation
    case thematicBreak
    case rawHTML
    case frontmatter
}

public struct OutlineItem: Sendable, Equatable {
    public let level: Int
    public let title: String
    /// UTF-16 location of the heading's line start.
    public let range: NSRange

    public init(level: Int, title: String, range: NSRange) {
        self.level = level
        self.title = title
        self.range = range
    }
}

public struct MarkdownSyntaxSpan: Sendable, Equatable {
    /// UTF-16 range, ready for AppKit. Never refers to bytes.
    public let range: NSRange
    public let kind: MarkdownSyntaxKind

    public init(range: NSRange, kind: MarkdownSyntaxKind) {
        self.range = range
        self.kind = kind
    }

    public func intersects(_ other: NSRange) -> Bool {
        range.location < other.location + other.length
            && other.location < range.location + range.length
    }
}

/// Text the editor sets in a heavier or slanted face when Styled Markdown
/// is on (markers included), in the manner of iA Writer.
public enum MarkdownTextStyle: Sendable, Equatable {
    case heading
    case strong
    case emphasis
}

public struct MarkdownStyleRange: Sendable, Equatable {
    public let range: NSRange
    public let style: MarkdownTextStyle

    public init(range: NSRange, style: MarkdownTextStyle) {
        self.range = range
        self.style = style
    }
}

public struct MarkdownParseOutput: Sendable {
    public let spans: [MarkdownSyntaxSpan]
    /// Sorted by location; nested styles overlap.
    public let styleRanges: [MarkdownStyleRange]
    public let nodeCount: Int
    public let outline: [OutlineItem]
    /// UTF-16 offsets of every line start, including 0.
    public let lineStarts: [Int]
    public let wordCount: Int
    public let characterCount: Int

    public init(
        spans: [MarkdownSyntaxSpan],
        nodeCount: Int,
        outline: [OutlineItem],
        lineStarts: [Int],
        wordCount: Int,
        characterCount: Int,
        styleRanges: [MarkdownStyleRange] = []
    ) {
        self.spans = spans
        self.styleRanges = styleRanges
        self.nodeCount = nodeCount
        self.outline = outline
        self.lineStarts = lineStarts
        self.wordCount = wordCount
        self.characterCount = characterCount
    }

    public var lineCount: Int { lineStarts.count }
}
