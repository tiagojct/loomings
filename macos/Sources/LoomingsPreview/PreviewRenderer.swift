import AppKit
import Foundation
import LoomingsMarkdown
import Markdown

public final class PreviewRenderer {
    public var theme: PreviewTheme

    public init(theme: PreviewTheme = .standard) {
        self.theme = theme
    }

    public func render(source: String, documentURL: URL?) -> PreviewDocument {
        let map = SourceMap(source)
        let frontmatter = MarkdownFrontmatter.range(in: source)
        let document = Document(parsing: source)
        var blocks: [PreviewBlock] = []

        for node in document.children {
            if let frontmatter,
               let range = map.nsRange(for: node.range),
               intersect(range, frontmatter) {
                continue
            }
            if let block = renderBlock(
                node,
                map: map,
                source: source,
                documentURL: documentURL
            ) {
                blocks.append(block)
            }
        }

        return PreviewDocument(blocks: blocks, html: blocks.map(\.html).joined())
    }

    // MARK: - Blocks

    private func renderBlock(
        _ node: Markup,
        map: SourceMap,
        source: String,
        documentURL: URL?
    ) -> PreviewBlock? {
        let range = map.nsRange(for: node.range) ?? NSRange(location: 0, length: 0)
        let line = max(0, (node.range?.lowerBound.line ?? 1) - 1)
        let sourceRange = range

        switch node {
        case let heading as Heading:
            let base = theme.headingFont(level: heading.level)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = heading.level <= 2 ? 20 : 14
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
            content.addAttribute(
                .loomingsSourceRange,
                value: NSValue(range: sourceRange),
                range: NSRange(location: 0, length: content.length)
            )
            return PreviewBlock(
                kind: .heading,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: "<h\(heading.level) data-line=\"\(line)\">\(inlineHTML(heading.children, documentURL: documentURL))</h\(heading.level)>\n"
            )

        case let paragraph as Paragraph:
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
            content.addAttribute(
                .loomingsSourceRange,
                value: NSValue(range: sourceRange),
                range: NSRange(location: 0, length: content.length)
            )
            return PreviewBlock(
                kind: .paragraph,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: "<p data-line=\"\(line)\">\(inlineHTML(paragraph.children, documentURL: documentURL))</p>\n"
            )

        case let list as UnorderedList:
            let content = renderList(list.children, ordered: false, start: 1, depth: 0, documentURL: documentURL)
            return PreviewBlock(
                kind: .list,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: listHTML(list.children, ordered: false, start: 1, line: line, documentURL: documentURL)
            )

        case let list as OrderedList:
            let content = renderList(list.children, ordered: true, start: Int(list.startIndex), depth: 0, documentURL: documentURL)
            return PreviewBlock(
                kind: .list,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: listHTML(list.children, ordered: true, start: Int(list.startIndex), line: line, documentURL: documentURL)
            )

        case let quote as BlockQuote:
            let content = renderQuote(quote, documentURL: documentURL)
            return PreviewBlock(
                kind: .quote,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: "<blockquote data-line=\"\(line)\">\n\(blockChildrenHTML(quote, documentURL: documentURL))</blockquote>\n"
            )

        case let code as CodeBlock:
            let content = renderCode(code, sourceRange: sourceRange, map: map, source: source)
            let fenced = isFencedCode(code, map: map, source: source)
            let language = code.language?.trimmingCharacters(in: .whitespaces)
            let escapedCode = escapeHTML(normalizedCode(code.code))
            let html: String
            if fenced {
                let classAttribute = language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
                html = "<pre><code data-line=\"\(line)\"\(classAttribute)>\(escapedCode)</code></pre>\n"
            } else {
                html = "<pre data-line=\"\(line)\"><code>\(escapedCode)</code></pre>\n"
            }
            return PreviewBlock(
                kind: .code,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html
            )

        case is ThematicBreak:
            let content = renderRule()
            return PreviewBlock(
                kind: .rule,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: "<hr data-line=\"\(line)\">\n"
            )

        case let table as Table:
            let (content, html) = renderTable(table, map: map, line: line, documentURL: documentURL)
            return PreviewBlock(
                kind: .table,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: html
            )

        case let htmlBlock as HTMLBlock:
            let text = htmlBlock.rawHTML
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
            content.addAttribute(
                .loomingsSourceRange,
                value: NSValue(range: sourceRange),
                range: NSRange(location: 0, length: content.length)
            )
            return PreviewBlock(
                kind: .html,
                sourceRange: sourceRange,
                sourceLine: line,
                attributed: content,
                html: "<p data-line=\"\(line)\">\(escapeHTML(text))</p>\n"
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
                html: "<p data-line=\"\(line)\">\(inlineHTML(node.children, documentURL: documentURL))</p>\n"
            )
        }
    }

    // MARK: - Attributed lists, quotes, code, rules, tables

    private func renderList(
        _ items: MarkupChildren,
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
            guard let listItem = item as? ListItem else { continue }
            let marker = ordered ? "\(number)." : "•"
            let checkbox: String
            switch listItem.checkbox {
            case .checked: checkbox = "[x] "
            case .unchecked: checkbox = "[ ] "
            case .none: checkbox = ""
            }

            var first = true
            for child in listItem.children {
                if let paragraph = child as? Paragraph {
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
                } else if let nested = child as? UnorderedList {
                    result.append(renderList(
                        nested.children,
                        ordered: false,
                        start: 1,
                        depth: depth + 1,
                        documentURL: documentURL
                    ))
                } else if let nested = child as? OrderedList {
                    result.append(renderList(
                        nested.children,
                        ordered: true,
                        start: Int(nested.startIndex),
                        depth: depth + 1,
                        documentURL: documentURL
                    ))
                } else if let code = child as? CodeBlock {
                    result.append(renderCode(
                        code,
                        sourceRange: NSRange(location: 0, length: 0),
                        map: SourceMap(""),
                        source: ""
                    ))
                } else if let quote = child as? BlockQuote {
                    result.append(renderQuote(quote, documentURL: documentURL))
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

    private func renderQuote(_ quote: BlockQuote, documentURL: URL?) -> NSAttributedString {
        let content = NSMutableAttributedString()
        for child in quote.children {
            if let paragraph = child as? Paragraph {
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
            } else if let heading = child as? Heading {
                content.append(inline(
                    heading.children,
                    base: [
                        .font: theme.headingFont(level: heading.level),
                        .foregroundColor: theme.secondaryTextColor,
                    ],
                    allowLinkify: true,
                    sourceRange: mapRange(of: heading),
                    documentURL: documentURL
                ))
                content.append(NSAttributedString(string: "\n"))
            } else if let code = child as? CodeBlock {
                content.append(renderCode(
                    code,
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
        _ code: CodeBlock,
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

        let value = normalizedCode(code.code)
        let content = NSMutableAttributedString(
            string: value + (value.hasSuffix("\n") ? "" : "\n"),
            attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.codeColor,
                .paragraphStyle: style,
            ]
        )
        content.addAttribute(
            .loomingsSourceRange,
            value: NSValue(range: sourceRange),
            range: NSRange(location: 0, length: content.length)
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
        _ table: Table,
        map: SourceMap,
        line: Int,
        documentURL: URL?
    ) -> (NSAttributedString, String) {
        let columnCount = table.maxColumnCount
        guard columnCount > 0 else {
            return (NSAttributedString(), "")
        }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true

        let result = NSMutableAttributedString()
        var html = "<table data-line=\"\(line)\">\n"

        let headLine = max(0, (table.head.range?.lowerBound.line ?? 1) - 1)
        let head = table.head
        html += "<thead data-line=\"\(headLine)\">\n"
        html += "<tr data-line=\"\(headLine)\">\n"

        for column in 0..<columnCount {
            let cell = column < head.childCount ? head.child(at: column) as? Table.Cell : nil
            let text = cell.map { inline($0.children, base: [
                .font: NSFontManager.shared.convert(theme.bodyFont, toHaveTrait: .boldFontMask),
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
                alignment: alignment(table, column),
                header: true
            )
            result.append(cellString)

            let alignmentStyle = alignmentStyle(table, column)
            let tag = alignmentStyle
            let cellHTML = cell.map { inlineHTML($0.children, documentURL: documentURL) } ?? ""
            html += "<th\(tag)>\(cellHTML)</th>\n"
        }
        html += "</tr>\n</thead>\n"

        if !table.body.isEmpty {
            let bodyLine = max(0, (table.body.range?.lowerBound.line ?? 1) - 1)
            html += "<tbody data-line=\"\(bodyLine)\">\n"
            var rowIndex = 1
            for row in table.body.rows {
                let rowLine = max(0, (row.range?.lowerBound.line ?? 1) - 1)
                html += "<tr data-line=\"\(rowLine)\">\n"
                for column in 0..<columnCount {
                    let cell = column < row.childCount ? row.child(at: column) as? Table.Cell : nil
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
                        alignment: alignment(table, column),
                        header: false
                    )
                    result.append(cellString)

                    let cellHTML = cell.map { inlineHTML($0.children, documentURL: documentURL) } ?? ""
                    html += "<td\(alignmentStyle(table, column))>\(cellHTML)</td>\n"
                }
                html += "</tr>\n"
                rowIndex += 1
            }
            html += "</tbody>\n"
        }

        html += "</table>\n"
        return (result, html)
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

    private func alignment(_ table: Table, _ column: Int) -> NSTextAlignment {
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

    private func alignmentStyle(_ table: Table, _ column: Int) -> String {
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
        _ nodes: MarkupChildren,
        base: [NSAttributedString.Key: Any],
        allowLinkify: Bool,
        sourceRange: NSRange,
        documentURL: URL?
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        for node in nodes {
            switch node {
            case let text as Text:
                let value = Typographer.transform(text.string)
                let start = result.length
                result.append(NSAttributedString(string: value, attributes: base))
                if allowLinkify {
                    applyLinkify(to: result, startingAt: start, attributes: base)
                }

            case let emphasis as Emphasis:
                var attributes = base
                attributes[.font] = font(base, adding: .italicFontMask)
                attributes[.foregroundColor] = theme.emphasisColor
                result.append(inline(
                    emphasis.children,
                    base: attributes,
                    allowLinkify: allowLinkify,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case let strong as Strong:
                var attributes = base
                attributes[.font] = font(base, adding: .boldFontMask)
                result.append(inline(
                    strong.children,
                    base: attributes,
                    allowLinkify: allowLinkify,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case let strike as Strikethrough:
                var attributes = base
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(inline(
                    strike.children,
                    base: attributes,
                    allowLinkify: allowLinkify,
                    sourceRange: sourceRange,
                    documentURL: documentURL
                ))

            case let code as InlineCode:
                var attributes = base
                attributes[.font] = theme.codeFont
                attributes[.backgroundColor] = theme.codeBackground
                attributes[.foregroundColor] = theme.codeColor
                result.append(NSAttributedString(string: code.code, attributes: attributes))

            case let link as Link:
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

            case let image as Image:
                result.append(renderImage(image, documentURL: documentURL))

            case is SoftBreak:
                result.append(NSAttributedString(string: " ", attributes: base))

            case is LineBreak:
                result.append(NSAttributedString(string: "\n", attributes: base))

            case let html as InlineHTML:
                result.append(NSAttributedString(string: html.rawHTML, attributes: base))

            default:
                if node.childCount > 0 {
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
        return NSFontManager.shared.convert(current, toHaveTrait: trait)
    }

    private func renderImage(_ image: Image, documentURL: URL?) -> NSAttributedString {
        let source = image.source ?? ""
        let alt = image.children
            .compactMap { $0 as? Text }
            .map(\.string)
            .joined()

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

    private func inlineHTML(_ nodes: MarkupChildren, documentURL: URL?) -> String {
        var result = ""
        for node in nodes {
            switch node {
            case let text as Text:
                let value = Typographer.transform(text.string)
                result += linkifiedHTML(value)

            case let emphasis as Emphasis:
                result += "<em>\(inlineHTML(emphasis.children, documentURL: documentURL))</em>"

            case let strong as Strong:
                result += "<strong>\(inlineHTML(strong.children, documentURL: documentURL))</strong>"

            case let strike as Strikethrough:
                result += "<s>\(inlineHTML(strike.children, documentURL: documentURL))</s>"

            case let code as InlineCode:
                result += "<code>\(escapeHTML(code.code))</code>"

            case let link as Link:
                let raw = link.destination ?? ""
                if PreviewURL.markdownItRejects(raw, isImage: false) {
                    result += escapeHTML("[\(plainText(link.children))](\(raw))")
                    break
                }
                let destination = PreviewURL.sanitizedLink(raw) ?? "#"
                let title = link.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
                result += "<a href=\"\(escapeAttribute(destination))\"\(title) rel=\"noopener noreferrer\">\(inlineHTML(link.children, documentURL: documentURL))</a>"

            case let image as Image:
                let raw = image.source ?? ""
                let altText = image.children.compactMap { $0 as? Text }.map(\.string).joined()
                if PreviewURL.markdownItRejects(raw, isImage: true) {
                    result += escapeHTML("![\(altText)](\(raw))")
                    break
                }
                let source = PreviewURL.sanitizedImage(raw) ?? "#"
                let alt = escapeAttribute(altText)
                let title = image.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
                result += "<img src=\"\(escapeAttribute(source))\" alt=\"\(alt)\"\(title)>"

            case is SoftBreak:
                result += "\n"

            case is LineBreak:
                result += "<br>\n"

            case let html as InlineHTML:
                result += escapeHTML(html.rawHTML)

            default:
                if node.childCount > 0 {
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

    private func blockChildrenHTML(_ node: Markup, documentURL: URL?) -> String {
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
        _ items: MarkupChildren,
        ordered: Bool,
        start: Int,
        line: Int,
        documentURL: URL?
    ) -> String {
        let tag = ordered ? "ol" : "ul"
        let startAttribute = ordered && start != 1 ? " start=\"\(start)\"" : ""
        var result = "<\(tag)\(startAttribute) data-line=\"\(line)\">\n"
        for item in items {
            guard let listItem = item as? ListItem else { continue }
            let itemLine = max(0, (listItem.range?.lowerBound.line ?? 1) - 1)
            result += "<li data-line=\"\(itemLine)\">"

            let checkbox: String
            switch listItem.checkbox {
            case .checked: checkbox = "[x] "
            case .unchecked: checkbox = "[ ] "
            case .none: checkbox = ""
            }

            var first = true
            for child in listItem.children {
                if let paragraph = child as? Paragraph {
                    if first {
                        result += checkbox
                    }
                    result += inlineHTML(paragraph.children, documentURL: documentURL)
                    first = false
                } else if let nested = child as? UnorderedList {
                    result += "\n" + listHTML(
                        nested.children,
                        ordered: false,
                        start: 1,
                        line: max(0, (nested.range?.lowerBound.line ?? 1) - 1),
                        documentURL: documentURL
                    )
                } else if let nested = child as? OrderedList {
                    result += "\n" + listHTML(
                        nested.children,
                        ordered: true,
                        start: Int(nested.startIndex),
                        line: max(0, (nested.range?.lowerBound.line ?? 1) - 1),
                        documentURL: documentURL
                    )
                } else if let quote = child as? BlockQuote {
                    result += "\n<blockquote data-line=\"\(max(0, (quote.range?.lowerBound.line ?? 1) - 1))\">\n"
                    result += blockChildrenHTML(quote, documentURL: documentURL)
                    result += "</blockquote>\n"
                }
            }
            result += "</li>\n"
        }
        result += "</\(tag)>\n"
        return result
    }

    private func plainText(_ nodes: MarkupChildren) -> String {
        var result = ""
        for node in nodes {
            if let text = node as? Text {
                result += text.string
            } else if let code = node as? InlineCode {
                result += code.code
            } else if node.childCount > 0 {
                result += plainText(node.children)
            }
        }
        return result
    }

    // MARK: - Shared helpers

    private func bodyStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.55
        style.paragraphSpacing = 12
        return style
    }

    private func normalizedCode(_ value: String) -> String {
        value.hasSuffix("\n") ? value : value + "\n"
    }

    private func mapRange(of node: Markup) -> NSRange {
        NSRange(location: 0, length: 0)
    }

    private func isFencedCode(_ code: CodeBlock, map: SourceMap, source: String) -> Bool {
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
