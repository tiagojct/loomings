import Foundation

/// One parse of a document with its source map, shared by several readers
/// so each does not parse again. The frontmatter is blanked (spaces, line
/// breaks kept) before cmark reads it, as the web port does: it is metadata,
/// and a fence or heading mark inside it must not change the document after
/// it. UTF-16 offsets stay those of `source`.
public final class ParsedMarkdown {
    public let source: String
    public let text: NSString
    public let map: SourceMap
    public let tree: MarkdownTree
    public let frontmatter: NSRange?

    public init(_ source: String) {
        self.source = source
        let text = source as NSString
        self.text = text
        let frontmatter = MarkdownFrontmatter.range(in: text)
        self.frontmatter = frontmatter
        let parsed = frontmatter.map { Self.blanking($0, in: text) } ?? source
        self.map = SourceMap(parsed)
        self.tree = MarkdownTree(parsing: parsed)
    }

    /// `text` with every unit of `range` but line breaks turned into a space.
    static func blanking(_ range: NSRange, in text: NSString) -> String {
        var units = [unichar](repeating: 0, count: text.length)
        text.getCharacters(&units, range: NSRange(location: 0, length: text.length))
        for index in range.location..<NSMaxRange(range) where units[index] != 0x0A && units[index] != 0x0D {
            units[index] = 0x20
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
