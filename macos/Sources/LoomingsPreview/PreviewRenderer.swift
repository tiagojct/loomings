import AppKit
import Foundation
import LoomingsMarkdown

public final class PreviewRenderer {
    public var theme: PreviewTheme {
        didSet {
            cache = [:]
            fonts = [:]
            headingFonts = [:]
        }
    }

    /// The live preview only shows attributed text; HTML is for export and
    /// costs about a third of a render, so the preview turns it off.
    public var producesHTML: Bool {
        didSet { if producesHTML != oldValue { cache = [:] } }
    }

    public init(theme: PreviewTheme = .standard, producesHTML: Bool = true) {
        self.theme = theme
        self.producesHTML = producesHTML
    }

    private func html(_ make: @autoclosure () -> String) -> String {
        producesHTML ? make() : ""
    }

    /// Rendered blocks from the previous render, by block text. Typing
    /// changes one block; the rest are reused instead of re-rendered. Only
    /// touched from one thread at a time (the window's preview queue).
    private struct CacheKey: Hashable {
        let text: String
        /// Reference definitions (`[id]: url`) elsewhere in the document
        /// decide where `[text][id]` links point, so they are part of the key.
        let definitions: Int
    }
    /// `stamp` is the render that last used the entry; older ones are swept.
    private struct CacheEntry {
        var block: PreviewBlock
        var stamp: Int
    }
    private var cache: [CacheKey: CacheEntry] = [:]
    private var renderCount = 0
    private var cacheDocumentURL: URL?

    /// How many blocks the last `render` reused.
    public private(set) var reusedBlockCount = 0

    private static let referenceDefinition = try! NSRegularExpression(
        pattern: #"^ {0,3}\[[^\]\n]+\]:[^\n]*"#,
        options: [.anchorsMatchLines]
    )

    public func render(source: String, documentURL: URL?) -> PreviewDocument {
        if cacheDocumentURL != documentURL {
            cache = [:]
            cacheDocumentURL = documentURL
        }

        let map = SourceMap(source)
        let nsSource = source as NSString
        let frontmatter = MarkdownFrontmatter.range(in: source)
        let tree = MarkdownTree(parsing: source)
        defer { withExtendedLifetime(tree) {} }

        var definitions = Hasher()
        Self.referenceDefinition.enumerateMatches(
            in: source,
            range: NSRange(location: 0, length: nsSource.length)
        ) { match, _, _ in
            if let match { definitions.combine(nsSource.substring(with: match.range)) }
        }
        let definitionsKey = definitions.finalize()

        renderCount += 1
        let stamp = renderCount
        var blocks: [PreviewBlock] = []
                var fresh: [(CacheKey, PreviewBlock)] = []
        var reused = 0

        for node in tree.document.children {
            let range = map.nsRange(for: node.range)
            if let frontmatter, let range, intersect(range, frontmatter) {
                continue
            }

            let line = node.startLine0
            // `substring(with:)` hands back a bridged NSString, which Swift
            // hashes about 100x slower than a native String; copy it first.
            let key = range.map {
                CacheKey(
                    text: String(decoding: nsSource.substring(with: $0).utf8, as: UTF8.self),
                    definitions: definitionsKey
                )
            }

            // One hash per hit: find the slot, then update it in place.
            if let key, let slot = cache.index(forKey: key) {
                let hit = cache.values[slot].block
                let block = hit.moved(toLocation: range?.location ?? 0, line: line)
                cache.values[slot] = CacheEntry(block: block, stamp: stamp)
                blocks.append(block)
                reused += 1
                continue
            }

            if let block = renderBlock(
                node,
                map: map,
                source: source,
                documentURL: documentURL
            ) {
                blocks.append(block)
                if let key { fresh.append((key, block)) }
            }
        }

        // Keep only what this render used, so the cache never outgrows the document.
        if cache.count != reused { cache = cache.filter { $0.value.stamp == stamp } }
        for (key, block) in fresh { cache[key] = CacheEntry(block: block, stamp: stamp) }
        reusedBlockCount = reused
        return PreviewDocument(blocks: blocks)
    }

    // MARK: - Blocks

    private func renderBlock(
        _ node: MarkdownNode,
        map: SourceMap,
        source: String,
        documentURL: URL?
    ) -> PreviewBlock? {
        let range = map.nsRange(for: node.range) ?? NSRange(location: 0, length: 0)
        let line = node.startLine0
        let sourceRange = range

        switch node.kind {
        case .heading:
            let heading = node
            let base = headingFont(heading.headingLevel)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = heading.headingLevel <= 2 ? 20 : 14
            paragraph.paragraphSpacing = 8
            paragraph.lineHeightMultiple = 1.2
            let content = inline(
                heading.children,
                base: [
                    .font: base,
                    .foregroundColor: theme.headingColor,
                ],
                allowLinkify: true,
                sourceRange: sourceRange,
                documentURL: documentURL
            )
            content.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
            content.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: 0, length: content.length)
            )
            return PreviewBlock(
                kind: .heading,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html("<h\(heading.headingLevel) data-line=\"\(line)\">\(inlineHTML(heading.children, documentURL: documentURL))</h\(heading.headingLevel)>\n")
            )

        case .paragraph:
            let paragraph = node
            let style = bodyStyle()
            let content = inline(
                paragraph.children,
                base: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.textColor,
                ],
                allowLinkify: true,
                sourceRange: sourceRange,
                documentURL: documentURL
            )
            content.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            content.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: content.length)
            )
            return PreviewBlock(
                kind: .paragraph,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html("<p data-line=\"\(line)\">\(inlineHTML(paragraph.children, documentURL: documentURL))</p>\n")
            )

        case .list:
            let ordered = node.isOrderedList
            let start = ordered ? node.listStart : 1
            let content = renderList(node.children, ordered: ordered, start: start, depth: 0, documentURL: documentURL)
            return PreviewBlock(
                kind: .list,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html(listHTML(node.children, ordered: ordered, start: start, line: line, documentURL: documentURL))
            )

        case .blockQuote:
            let quote = node
            let content = renderQuote(quote, documentURL: documentURL)
            return PreviewBlock(
                kind: .quote,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html("<blockquote data-line=\"\(line)\">\n\(blockChildrenHTML(quote, documentURL: documentURL))</blockquote>\n")
            )

        case .codeBlock:
            let code = node
            let content = renderCode(code, sourceRange: sourceRange, map: map, source: source)
            let fenced = isFencedCode(code, map: map, source: source)
            let language = code.fenceInfo?.trimmingCharacters(in: .whitespaces)
            var codeHTML = ""
            if producesHTML {
                let escapedCode = escapeHTML(normalizedCode(code.literal))
                if fenced {
                    let classAttribute = language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
                    codeHTML = "<pre><code data-line=\"\(line)\"\(classAttribute)>\(escapedCode)</code></pre>\n"
                } else {
                    codeHTML = "<pre data-line=\"\(line)\"><code>\(escapedCode)</code></pre>\n"
                }
            }
            return PreviewBlock(
                kind: .code,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: codeHTML
            )

        case .thematicBreak:
            let content = renderRule()
            return PreviewBlock(
                kind: .rule,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html("<hr data-line=\"\(line)\">\n")
            )

        case .table:
            let (content, tableHTML) = renderTable(node, map: map, line: line, documentURL: documentURL)
            return PreviewBlock(
                kind: .table,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: tableHTML
            )

        case .htmlBlock:
            let text = node.literal
                .trimmingCharacters(in: .newlines)
            let style = bodyStyle()
            let content = NSMutableAttributedString(
                string: text + "\n",
                attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.textColor,
                    .paragraphStyle: style,
                ]
            )
            return PreviewBlock(
                kind: .html,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html("<p data-line=\"\(line)\">\(escapeHTML(text))</p>\n")
            )

        default:
            let style = bodyStyle()
            let content = inline(
                node.children,
                base: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.textColor,
                ],
                allowLinkify: true,
                sourceRange: sourceRange,
                documentURL: documentURL
            )
            content.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            content.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: content.length)
            )
            return PreviewBlock(
                kind: .paragraph,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html("<p data-line=\"\(line)\">\(inlineHTML(node.children, documentURL: documentURL))</p>\n")
            )
        }
    }

    // MARK: - Attributed lists, quotes, code, rules, tables

    private func renderList(
        _ items: MarkdownChildren,
        ordered: Bool,
        start: Int,
        depth: Int,
        documentURL: URL?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var number = start
        let indent = CGFloat(depth) * 22
        let markerWidth: CGFloat = ordered ? 30 : 20

        for item in items {
            guard item.kind == .item else { continue }
            let listItem = item
            let marker = ordered ? "\(number)." : "•"
            let checkbox = checkboxPrefix(listItem)

            var first = true
            for child in listItem.children {
                if child.kind == .paragraph {
                    let paragraph = child
                    let style = listStyle(
                        indent: indent,
                        markerWidth: markerWidth,
                        firstLine: first
                    )
                    let content = NSMutableAttributedString()
                    if first {
                        content.append(NSAttributedString(
                            string: "\(marker)\t\(checkbox)",
                            attributes: [
                                .font: theme.bodyFont,
                                .foregroundColor: theme.markerColor,
                            ]
                        ))
                    }
                    content.append(inline(
                        paragraph.children,
                        base: [
                            .font: theme.bodyFont,
                            .foregroundColor: theme.textColor,
                        ],
                        allowLinkify: true,
                        sourceRange: mapRange(of: paragraph),
                        documentURL: documentURL
                    ))
                    content.append(NSAttributedString(string: "\n"))
                    content.addAttribute(
                        .paragraphStyle,
                        value: style,
                        range: NSRange(location: 0, length: content.length)
                    )
                    result.append(content)
                    first = false
                } else if child.kind == .list {
                    let nestedOrdered = child.isOrderedList
                    result.append(renderList(
                        child.children,
                        ordered: nestedOrdered,
                        start: nestedOrdered ? child.listStart : 1,
                        depth: depth + 1,
                        documentURL: documentURL
                    ))
                } else if child.kind == .codeBlock {
                    result.append(renderCode(
                        child,
                        sourceRange: NSRange(location: 0, length: 0),
                        map: SourceMap(""),
                        source: ""
                    ))
                } else if child.kind == .blockQuote {
                    result.append(renderQuote(child, documentURL: documentURL))
                }
            }
            number += 1
        }
        return result
    }

    private func listStyle(indent: CGFloat, markerWidth: CGFloat, firstLine: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent + markerWidth
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: indent + markerWidth),
        ]
        style.paragraphSpacing = 4
        style.lineHeightMultiple = 1.35
        return style
    }

    private func renderQuote(_ quote: MarkdownNode, documentURL: URL?) -> NSAttributedString {
        let content = NSMutableAttributedString()
        for child in quote.children {
            if child.kind == .paragraph {
                let paragraph = child
                content.append(inline(
                    paragraph.children,
                    base: [
                        .font: theme.bodyFont,
                        .foregroundColor: theme.secondaryTextColor,
                    ],
                    allowLinkify: true,
                    sourceRange: mapRange(of: paragraph),
                    documentURL: documentURL
                ))
                content.append(NSAttributedString(string: "\n"))
            } else if child.kind == .heading {
                let heading = child
                content.append(inline(
                    heading.children,
                    base: [
                        .font: headingFont(heading.headingLevel),
                        .foregroundColor: theme.secondaryTextColor,
                    ],
                    allowLinkify: true,
                    sourceRange: mapRange(of: heading),
                    documentURL: documentURL
                ))
                content.append(NSAttributedString(string: "\n"))
            } else if child.kind == .codeBlock {
                content.append(renderCode(
                    child,
                    sourceRange: NSRange(location: 0, length: 0),
                    map: SourceMap(""),
                    source: ""
                ))
            }
        }

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 16
        style.headIndent = 16
        style.paragraphSpacing = 10
        style.lineHeightMultiple = 1.4
        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(theme.quoteBorderColor, for: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        style.textBlocks = [block]

        content.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: content.length)
        )
        content.addAttribute(
            .obliqueness,
            value: 0.12,
            range: NSRange(location: 0, length: content.length)
        )
        return content
    }

    private func renderCode(
        _ code: MarkdownNode,
        sourceRange: NSRange,
        map: SourceMap,
        source: String
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.paragraphSpacing = 12
        style.paragraphSpacingBefore = 8
        style.lineHeightMultiple = 1.35

        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(theme.borderColor)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.backgroundColor = theme.codeBackground
        style.textBlocks = [block]

        let value = normalizedCode(code.literal)
        let content = NSMutableAttributedString(
            string: value + (value.hasSuffix("\n") ? "" : "\n"),
            attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.codeColor,
                .paragraphStyle: style,
            ]
        )
        return content
    }

    private func renderRule() -> NSAttributedString {
        let lineColor = theme.borderColor
        let image = NSImage(size: NSSize(width: 600, height: 2), flipped: false) { rect in
            lineColor.setFill()
            rect.fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: 4, width: 600, height: 2)

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 12

        let content = NSMutableAttributedString(attachment: attachment)
        content.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        content.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: content.length)
        )
        return content
    }

    private func renderTable(
        _ table: MarkdownNode,
        map: SourceMap,
        line: Int,
        documentURL: URL?
    ) -> (NSAttributedString, String) {
        let parts = TableParts(table)
        let columnCount = parts.maxColumnCount
        guard columnCount > 0 else {
            return (NSAttributedString(), "")
        }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true

        let result = NSMutableAttributedString()
        var html = "<table data-line=\"\(line)\">\n"

        let headLine = parts.head?.startLine0 ?? 0
        let head = parts.head
        html += "<thead data-line=\"\(headLine)\">\n"
        html += "<tr data-line=\"\(headLine)\">\n"

        for column in 0..<columnCount {
            let cell = head?.child(at: column)
            let text = cell.map { inline($0.children, base: [
                .font: converted(theme.bodyFont, adding: .boldFontMask),
                .foregroundColor: theme.textColor,
            ], allowLinkify: true, sourceRange: map.nsRange(for: $0.range) ?? NSRange(location: 0, length: 0), documentURL: documentURL) }
                ?? NSAttributedString(string: "")
            let cellString = NSMutableAttributedString(attributedString: text)
            cellString.append(NSAttributedString(string: "\n"))
            applyTableCell(
                cellString,
                table: textTable,
                row: 0,
                column: column,
                alignment: alignment(parts, column),
                header: true
            )
            result.append(cellString)

            let alignmentStyle = alignmentStyle(parts, column)
            let tag = alignmentStyle
            let cellHTML = producesHTML ? cell.map { inlineHTML($0.children, documentURL: documentURL) } ?? "" : ""
            html += "<th\(tag)>\(cellHTML)</th>\n"
        }
        html += "</tr>\n</thead>\n"

        if let firstRow = parts.rows.first {
            let bodyLine = firstRow.startLine0
            html += "<tbody data-line=\"\(bodyLine)\">\n"
            var rowIndex = 1
            for row in parts.rows {
                let rowLine = row.startLine0
                html += "<tr data-line=\"\(rowLine)\">\n"
                for column in 0..<columnCount {
                    let cell = row.child(at: column)
                    let text = cell.map { inline($0.children, base: [
                        .font: theme.bodyFont,
                        .foregroundColor: theme.textColor,
                    ], allowLinkify: true, sourceRange: map.nsRange(for: $0.range) ?? NSRange(location: 0, length: 0), documentURL: documentURL) }
                        ?? NSAttributedString(string: "")
                    let cellString = NSMutableAttributedString(attributedString: text)
                    cellString.append(NSAttributedString(string: "\n"))
                    applyTableCell(
                        cellString,
                        table: textTable,
                        row: rowIndex,
                        column: column,
                        alignment: alignment(parts, column),
                        header: false
                    )
                    result.append(cellString)

                    let cellHTML = producesHTML ? cell.map { inlineHTML($0.children, documentURL: documentURL) } ?? "" : ""
                    html += "<td\(alignmentStyle(parts, column))>\(cellHTML)</td>\n"
                }
                html += "</tr>\n"
                rowIndex += 1
            }
            html += "</tbody>\n"
        }

        html += "</table>\n"
        return (result, producesHTML ? html : "")
    }

    private func applyTableCell(
        _ string: NSMutableAttributedString,
        table: NSTextTable,
        row: Int,
        column: Int,
        alignment: NSTextAlignment,
        header: Bool
    ) {
        let block = NSTextTableBlock(
            table: table,
            startingRow: row,
            rowSpan: 1,
            startingColumn: column,
            columnSpan: 1
        )
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(theme.borderColor)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        if header {
            block.backgroundColor = theme.codeBackground
        }

        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.alignment = alignment
        style.lineHeightMultiple = 1.25
        string.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: string.length)
        )
    }

    private func alignment(_ table: TableParts, _ column: Int) -> NSTextAlignment {
        guard column < table.columnAlignments.count,
              let value = table.columnAlignments[column] else {
            return .left
        }
        switch value {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    private func alignmentStyle(_ table: TableParts, _ column: Int) -> String {
        guard column < table.columnAlignments.count,
              let value = table.columnAlignments[column] else {
            return ""
        }
        switch value {
        case .left: return " style=\"text-align:left\""
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        }
    }

    // MARK: - Inline attributed text

    private func inline(
        _ nodes: MarkdownChildren,
        base: [NSAttributedString.Key: Any],
        allowLinkify: Bool,
        sourceRange: NSRange,
        documentURL: URL?
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        for node in nodes {
            switch node.kind {
            case .text:
                let value = Typographer.transform(node.literal)
                let start = result.length
                result.append(NSAttributedString(string: value, attributes: base))
                if allowLinkify {
                    applyLinkify(to: result, startingAt: start, attributes: base)
                }

            case .emphasis:
                var attributes = base
                attributes[.font] = font(base, adding: .italicFontMask)
                attributes[.foregroundColor] = theme.emphasisColor
                result.append(inline(
                    node.children,
                    base: attributes,
                    allowLinkify: allowLinkify,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case .strong:
                var attributes = base
                attributes[.font] = font(base, adding: .boldFontMask)
                result.append(inline(
                    node.children,
                    base: attributes,
                    allowLinkify: allowLinkify,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case .strikethrough:
                var attributes = base
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(inline(
                    node.children,
                    base: attributes,
                    allowLinkify: allowLinkify,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case .code:
                var attributes = base
                attributes[.font] = theme.codeFont
                attributes[.backgroundColor] = theme.codeBackground
                attributes[.foregroundColor] = theme.codeColor
                result.append(NSAttributedString(string: node.literal, attributes: attributes))

            case .link:
                let link = node
                let destination = link.destination ?? ""
                if PreviewURL.markdownItRejects(destination, isImage: false) {
                    let literal = "[\(plainText(link.children))](\(destination))"
                    result.append(NSAttributedString(string: literal, attributes: base))
                    break
                }
                let safe = PreviewURL.sanitizedLink(destination)
                var attributes = base
                if let safe, let url = URL(string: safe) {
                    attributes[.link] = url
                    attributes[.foregroundColor] = theme.linkColor
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if let title = link.title {
                    attributes[.toolTip] = title
                }
                result.append(inline(
                    link.children,
                    base: attributes,
                    allowLinkify: false,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case .image:
                result.append(renderImage(node, documentURL: documentURL))

            case .softBreak:
                result.append(NSAttributedString(string: " ", attributes: base))

            case .lineBreak:
                result.append(NSAttributedString(string: "\n", attributes: base))

            case .inlineHTML:
                result.append(NSAttributedString(string: node.literal, attributes: base))

            default:
                if node.hasChildren {
                    result.append(inline(
                        node.children,
                        base: base,
                        allowLinkify: allowLinkify,
                        sourceRange: sourceRange,
                        documentURL: documentURL
                    ))
                }
            }
        }

        return result
    }

    private func font(
        _ attributes: [NSAttributedString.Key: Any],
        adding trait: NSFontTraitMask
    ) -> NSFont {
        let current = attributes[.font] as? NSFont ?? theme.bodyFont
        return converted(current, adding: trait)
    }

    /// Font conversion goes through Core Text matching and costs more than
    /// the rest of an inline run, so each result is kept for the theme.
    private struct FontKey: Hashable {
        let name: String
        let size: CGFloat
        let trait: UInt
    }
    private var fonts: [FontKey: NSFont] = [:]
    private var headingFonts: [Int: NSFont] = [:]

    private func converted(_ font: NSFont, adding trait: NSFontTraitMask) -> NSFont {
        let key = FontKey(name: font.fontName, size: font.pointSize, trait: trait.rawValue)
        if let known = fonts[key] { return known }
        let result = NSFontManager.shared.convert(font, toHaveTrait: trait)
        fonts[key] = result
        return result
    }

    private func headingFont(_ level: Int) -> NSFont {
        if let known = headingFonts[level] { return known }
        let result = theme.headingFont(level: level)
        headingFonts[level] = result
        return result
    }

    private func renderImage(_ image: MarkdownNode, documentURL: URL?) -> NSAttributedString {
        let source = image.destination ?? ""
        let alt = altText(image)

        if PreviewURL.markdownItRejects(source, isImage: true) {
            return NSAttributedString(
                string: "![\(alt)](\(source))",
                attributes: [
                    .font: theme.bodyFont,
                    .foregroundColor: theme.textColor,
                ]
            )
        }

        let safe = PreviewURL.sanitizedImage(source)

        let attachment = NSTextAttachment()
        attachment.image = NSImage(
            systemSymbolName: "photo",
            accessibilityDescription: alt.isEmpty ? "Image" : alt
        )
        attachment.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)

        let result = NSMutableAttributedString(attachment: attachment)
        if let safe {
            result.addAttribute(
                .loomingsImageURL,
                value: safe,
                range: NSRange(location: 0, length: result.length)
            )
        }
        result.addAttribute(
            .loomingsImageAlt,
            value: alt,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private func applyLinkify(
        to string: NSMutableAttributedString,
        startingAt start: Int,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard start < string.length else { return }
        let range = NSRange(location: start, length: string.length - start)
        let text = string.attributedSubstring(from: range).string
        for match in Linkifier.matches(in: text) {
            let target = NSRange(
                location: start + match.range.location,
                length: match.range.length
            )
            guard let url = URL(string: match.url) else { continue }
            string.addAttributes(
                [
                    .link: url,
                    .foregroundColor: theme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: target
            )
        }
    }

    // MARK: - HTML inline

    private func inlineHTML(_ nodes: MarkdownChildren, documentURL: URL?) -> String {
        var result = ""
        for node in nodes {
            switch node.kind {
            case .text:
                let value = Typographer.transform(node.literal)
                result += linkifiedHTML(value)

            case .emphasis:
                result += "<em>\(inlineHTML(node.children, documentURL: documentURL))</em>"

            case .strong:
                result += "<strong>\(inlineHTML(node.children, documentURL: documentURL))</strong>"

            case .strikethrough:
                result += "<s>\(inlineHTML(node.children, documentURL: documentURL))</s>"

            case .code:
                result += "<code>\(escapeHTML(node.literal))</code>"

            case .link:
                let link = node
                let raw = link.destination ?? ""
                if PreviewURL.markdownItRejects(raw, isImage: false) {
                    result += escapeHTML("[\(plainText(link.children))](\(raw))")
                    break
                }
                let destination = PreviewURL.sanitizedLink(raw) ?? "#"
                let title = link.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
                result += "<a href=\"\(escapeAttribute(destination))\"\(title) rel=\"noopener noreferrer\">\(inlineHTML(link.children, documentURL: documentURL))</a>"

            case .image:
                let image = node
                let raw = image.destination ?? ""
                let altText = altText(image)
                if PreviewURL.markdownItRejects(raw, isImage: true) {
                    result += escapeHTML("![\(altText)](\(raw))")
                    break
                }
                let source = PreviewURL.sanitizedImage(raw) ?? "#"
                let alt = escapeAttribute(altText)
                let title = image.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
                result += "<img src=\"\(escapeAttribute(source))\" alt=\"\(alt)\"\(title)>"

            case .softBreak:
                result += "\n"

            case .lineBreak:
                result += "<br>\n"

            case .inlineHTML:
                result += escapeHTML(node.literal)

            default:
                if node.hasChildren {
                    result += inlineHTML(node.children, documentURL: documentURL)
                }
            }
        }
        return result
    }

    private func linkifiedHTML(_ text: String) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in Linkifier.matches(in: text) {
            if match.range.location > cursor {
                result += escapeHTML(ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                )))
            }
            let label = escapeHTML(ns.substring(with: match.range))
            result += "<a href=\"\(escapeAttribute(match.url))\" rel=\"noopener noreferrer\">\(label)</a>"
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += escapeHTML(ns.substring(with: NSRange(
                location: cursor,
                length: ns.length - cursor
            )))
        }
        return result
    }

    // MARK: - HTML blocks

    private func blockChildrenHTML(_ node: MarkdownNode, documentURL: URL?) -> String {
        var result = ""
        for child in node.children {
            if let block = renderBlock(
                child,
                map: SourceMap(""),
                source: "",
                documentURL: documentURL
            ) {
                result += block.html
            }
        }
        return result
    }

    private func listHTML(
        _ items: MarkdownChildren,
        ordered: Bool,
        start: Int,
        line: Int,
        documentURL: URL?
    ) -> String {
        let tag = ordered ? "ol" : "ul"
        let startAttribute = ordered && start != 1 ? " start=\"\(start)\"" : ""
        var result = "<\(tag)\(startAttribute) data-line=\"\(line)\">\n"
        for item in items {
            guard item.kind == .item else { continue }
            let listItem = item
            let itemLine = listItem.startLine0
            result += "<li data-line=\"\(itemLine)\">"

            let checkbox = checkboxPrefix(listItem)

            var first = true
            for child in listItem.children {
                if child.kind == .paragraph {
                    if first {
                        result += checkbox
                    }
                    result += inlineHTML(child.children, documentURL: documentURL)
                    first = false
                } else if child.kind == .list {
                    let nestedOrdered = child.isOrderedList
                    result += "\n" + listHTML(
                        child.children,
                        ordered: nestedOrdered,
                        start: nestedOrdered ? child.listStart : 1,
                        line: child.startLine0,
                        documentURL: documentURL
                    )
                } else if child.kind == .blockQuote {
                    let quote = child
                    result += "\n<blockquote data-line=\"\(quote.startLine0)\">\n"
                    result += blockChildrenHTML(quote, documentURL: documentURL)
                    result += "</blockquote>\n"
                }
            }
            result += "</li>\n"
        }
        result += "</\(tag)>\n"
        return result
    }

    private func plainText(_ nodes: MarkdownChildren) -> String {
        var result = ""
        for node in nodes {
            if node.kind == .text {
                result += node.literal
            } else if node.kind == .code {
                result += node.literal
            } else if node.hasChildren {
                result += plainText(node.children)
            }
        }
        return result
    }

    // MARK: - Shared helpers

    private func checkboxPrefix(_ item: MarkdownNode) -> String {
        switch item.checkbox {
        case .checked: return "[x] "
        case .unchecked: return "[ ] "
        case nil: return ""
        }
    }

    private func altText(_ image: MarkdownNode) -> String {
        image.children.filter { $0.kind == .text }.map(\.literal).joined()
    }

    private func bodyStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.55
        style.paragraphSpacing = 12
        return style
    }

    private func normalizedCode(_ value: String) -> String {
        value.hasSuffix("\n") ? value : value + "\n"
    }

    private func mapRange(of node: MarkdownNode) -> NSRange {
        NSRange(location: 0, length: 0)
    }

    private func isFencedCode(_ code: MarkdownNode, map: SourceMap, source: String) -> Bool {
        guard let range = map.nsRange(for: code.range) else { return false }
        let text = source as NSString
        guard range.location < text.length else { return false }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        var cursor = line.location
        var spaces = 0
        while cursor < line.location + line.length, spaces < 4 {
            let character = text.character(at: cursor)
            if character == 0x20 || character == 0x09 {
                cursor += 1
                spaces += 1
            } else {
                break
            }
        }
        guard cursor < line.location + line.length else { return false }
        let character = text.character(at: cursor)
        return character == 0x60 || character == 0x7E
    }

    private func intersect(_ left: NSRange, _ right: NSRange) -> Bool {
        left.location < right.location + right.length
            && right.location < left.location + left.length
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// A GFM table as swift-markdown presented it: the header row, the body rows
/// and the column alignments.
private struct TableParts {
    let head: MarkdownNode?
    let rows: [MarkdownNode]
    let columnAlignments: [MarkdownColumnAlignment?]

    init(_ table: MarkdownNode) {
        var head: MarkdownNode?
        var rows: [MarkdownNode] = []
        for child in table.children {
            switch child.kind {
            case .tableHead where head == nil && rows.isEmpty: head = child
            case .tableRow: rows.append(child)
            default: break
            }
        }
        self.head = head
        self.rows = rows
        self.columnAlignments = table.columnAlignments
    }

    var maxColumnCount: Int {
        rows.reduce(head?.childCount ?? 0) { max($0, $1.childCount) }
    }
}
