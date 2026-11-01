import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// A cmark-gfm parse, read in place.
///
/// swift-markdown copies every cmark node into a Swift tree before anyone can
/// read it; at 1 MB that copy is about 170 ms of a 200 ms parse. The editor
/// and the preview only read the tree once, so they walk cmark's own nodes
/// instead. Options and extensions match `Document(parsing:)`: smart
/// punctuation, source positions, table spans, and the table, strikethrough
/// and tasklist extensions.
///
/// Nodes are borrowed pointers into this tree. Keep the tree alive while any
/// node is in use (`withExtendedLifetime`, or a local that outlives the walk).
public final class MarkdownTree {
    public let document: MarkdownNode
    private let root: UnsafeMutablePointer<cmark_node>

    public init(parsing source: String) {
        cmark_gfm_core_extensions_ensure_registered()
        let options = CMARK_OPT_TABLE_SPANS | CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS
        let parser = cmark_parser_new(options)!
        for name in ["table", "strikethrough", "tasklist"] {
            if let syntax = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntax)
            }
        }
        var source = source
        source.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { chars in
                if let base = chars.baseAddress {
                    cmark_parser_feed(parser, base, chars.count)
                }
            }
        }
        root = cmark_parser_finish(parser)
        cmark_parser_free(parser)
        document = MarkdownNode(root)
    }

    deinit {
        cmark_node_free(root)
    }
}

public enum MarkdownNodeKind: Equatable, Sendable {
    case document
    case blockQuote
    case list
    case item
    case codeBlock
    case htmlBlock
    case customBlock
    case paragraph
    case heading
    case thematicBreak
    case text
    case softBreak
    case lineBreak
    case code
    case inlineHTML
    case customInline
    case emphasis
    case strong
    case link
    case image
    case strikethrough
    case table
    case tableHead
    case tableRow
    case tableCell
    case other
}

public enum MarkdownCheckbox: Sendable {
    case checked
    case unchecked
}

public enum MarkdownColumnAlignment: Sendable {
    case left
    case center
    case right
}

/// cmark's 1-based line and UTF-8 column. The upper bound is exclusive, and
/// code spans include their backticks, as in swift-markdown's `SourceRange`.
public struct MarkdownSourceRange: Equatable, Sendable {
    public var startLine: Int
    public var startColumn: Int
    public var endLine: Int
    public var endColumn: Int
}

public struct MarkdownNode {
    let pointer: UnsafeMutablePointer<cmark_node>

    init(_ pointer: UnsafeMutablePointer<cmark_node>) {
        self.pointer = pointer
    }

    // MARK: Kind

    public var kind: MarkdownNodeKind {
        let type = cmark_node_get_type(pointer)
        switch type {
        case CMARK_NODE_DOCUMENT: return .document
        case CMARK_NODE_BLOCK_QUOTE: return .blockQuote
        case CMARK_NODE_LIST: return .list
        case CMARK_NODE_ITEM: return .item
        case CMARK_NODE_CODE_BLOCK: return .codeBlock
        case CMARK_NODE_HTML_BLOCK: return .htmlBlock
        case CMARK_NODE_CUSTOM_BLOCK: return .customBlock
        case CMARK_NODE_PARAGRAPH: return .paragraph
        case CMARK_NODE_HEADING: return .heading
        case CMARK_NODE_THEMATIC_BREAK: return .thematicBreak
        case CMARK_NODE_TEXT: return .text
        case CMARK_NODE_SOFTBREAK: return .softBreak
        case CMARK_NODE_LINEBREAK: return .lineBreak
        case CMARK_NODE_CODE: return .code
        case CMARK_NODE_HTML_INLINE: return .inlineHTML
        case CMARK_NODE_CUSTOM_INLINE: return .customInline
        case CMARK_NODE_EMPH: return .emphasis
        case CMARK_NODE_STRONG: return .strong
        case CMARK_NODE_LINK: return .link
        case CMARK_NODE_IMAGE: return .image
        default:
            let kind = Self.extensionKind(type, pointer)
            // Header and body rows share one node type; a flag tells them apart.
            if kind == .tableRow || kind == .tableHead {
                return cmark_gfm_extensions_get_table_row_is_header(pointer) != 0 ? .tableHead : .tableRow
            }
            return kind
        }
    }

    /// Extension node types are numbered when the extensions register, so
    /// they are learned from the type string once and cached by number.
    nonisolated(unsafe) private static var extensionKinds: [UInt32: MarkdownNodeKind] = [:]
    private static let extensionLock = NSLock()

    private static func extensionKind(
        _ type: cmark_node_type,
        _ pointer: UnsafeMutablePointer<cmark_node>
    ) -> MarkdownNodeKind {
        extensionLock.lock()
        defer { extensionLock.unlock() }
        if let known = extensionKinds[type.rawValue] { return known }
        let name = cmark_node_get_type_string(pointer).map { String(cString: $0) } ?? ""
        let kind: MarkdownNodeKind
        switch name {
        case "strikethrough": kind = .strikethrough
        case "table": kind = .table
        case "table_header", "table_row": kind = .tableRow
        case "table_cell": kind = .tableCell
        default: kind = .other
        }
        extensionKinds[type.rawValue] = kind
        return kind
    }

    // MARK: Children

    public var firstChild: MarkdownNode? {
        cmark_node_first_child(pointer).map(MarkdownNode.init)
    }

    public var nextSibling: MarkdownNode? {
        cmark_node_next(pointer).map(MarkdownNode.init)
    }

    public var children: MarkdownChildren { MarkdownChildren(first: firstChild) }

    public var childCount: Int {
        var count = 0
        var child = cmark_node_first_child(pointer)
        while let current = child {
            count += 1
            child = cmark_node_next(current)
        }
        return count
    }

    public var hasChildren: Bool { cmark_node_first_child(pointer) != nil }

    public func child(at index: Int) -> MarkdownNode? {
        var position = 0
        var child = cmark_node_first_child(pointer)
        while let current = child {
            if position == index { return MarkdownNode(current) }
            position += 1
            child = cmark_node_next(current)
        }
        return nil
    }

    // MARK: Positions

    public var range: MarkdownSourceRange? {
        let startLine = Int(cmark_node_get_start_line(pointer))
        let startColumn = Int(cmark_node_get_start_column(pointer))
        guard startLine > 0, startColumn > 0 else { return nil }
        let endLine = Int(cmark_node_get_end_line(pointer))
        let endColumn = Int(cmark_node_get_end_column(pointer)) + 1
        guard endLine > 0, endColumn > 0 else { return nil }
        let ticks = Int(cmark_node_get_backtick_count(pointer))
        let result = MarkdownSourceRange(
            startLine: startLine,
            startColumn: startColumn - ticks,
            endLine: endLine,
            endColumn: endColumn + ticks
        )
        guard (result.startLine, result.startColumn) <= (result.endLine, result.endColumn) else {
            return nil
        }
        return result
    }

    /// 0-based first line, as markdown-it's `data-line`.
    public var startLine0: Int {
        max(0, Int(cmark_node_get_start_line(pointer)) - 1)
    }

    // MARK: Content

    /// Text, code span, code block and HTML content.
    public var literal: String {
        cmark_node_get_literal(pointer).map { String(cString: $0) } ?? ""
    }

    public var headingLevel: Int { Int(cmark_node_get_heading_level(pointer)) }

    public var isOrderedList: Bool { cmark_node_get_list_type(pointer) == CMARK_ORDERED_LIST }

    public var listStart: Int { Int(cmark_node_get_list_start(pointer)) }

    /// The info string of a fenced code block, or nil when it is empty.
    public var fenceInfo: String? { nonEmpty(cmark_node_get_fence_info(pointer)) }

    /// Link destination or image source, or nil when empty.
    public var destination: String? { nonEmpty(cmark_node_get_url(pointer)) }

    public var title: String? { nonEmpty(cmark_node_get_title(pointer)) }

    /// A task-list item's box, or nil for an ordinary item.
    public var checkbox: MarkdownCheckbox? {
        guard kind == .item, let type = cmark_node_get_type_string(pointer),
              strcmp(type, "tasklist") == 0 else { return nil }
        return cmark_gfm_extensions_get_tasklist_item_checked(pointer) ? .checked : .unchecked
    }

    public var columnAlignments: [MarkdownColumnAlignment?] {
        let count = Int(cmark_gfm_extensions_get_table_columns(pointer))
        guard count > 0, let raw = cmark_gfm_extensions_get_table_alignments(pointer) else { return [] }
        return (0..<count).map { column in
            switch raw[column] {
            case UInt8(ascii: "l"): return .left
            case UInt8(ascii: "c"): return .center
            case UInt8(ascii: "r"): return .right
            default: return nil
            }
        }
    }

    private func nonEmpty(_ value: UnsafePointer<CChar>?) -> String? {
        guard let value, value.pointee != 0 else { return nil }
        return String(cString: value)
    }
}

public struct MarkdownChildren: Sequence {
    let first: MarkdownNode?

    public func makeIterator() -> Iterator { Iterator(upcoming: first) }

    public struct Iterator: IteratorProtocol {
        var upcoming: MarkdownNode?

        public mutating func next() -> MarkdownNode? {
            guard let current = upcoming else { return nil }
            upcoming = current.nextSibling
            return current
        }
    }
}
