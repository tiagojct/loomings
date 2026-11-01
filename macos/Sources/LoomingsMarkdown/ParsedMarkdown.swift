import Foundation

/// One parse of a document with its source map, shared by several readers
/// so each does not parse again.
public final class ParsedMarkdown {
    public let source: String
    public let text: NSString
    public let map: SourceMap
    public let tree: MarkdownTree
    public let frontmatter: NSRange?

    public init(_ source: String) {
        self.source = source
        self.text = source as NSString
        self.map = SourceMap(source)
        self.tree = MarkdownTree(parsing: source)
        self.frontmatter = MarkdownFrontmatter.range(in: source as NSString)
    }
}
