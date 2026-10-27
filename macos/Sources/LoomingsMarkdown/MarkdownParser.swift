import Foundation
import Markdown

/// Walks the swift-markdown syntax tree once and produces the source ranges
/// the editor dims. Parsing is pure: no AppKit, no text storage, no state.
public enum MarkdownParser {
    public static func parse(_ source: String, options: ParseOptions = []) -> MarkdownParseOutput {
        let map = SourceMap(source)
        let text = source as NSString
        let document = Document(parsing: source, options: options)

        var spans: [MarkdownSyntaxSpan] = []
        var outline: [OutlineItem] = []
        var nodeCount = 0

        var stack: [Markup] = [document]
        while let node = stack.popLast() {
            nodeCount += 1
            emit(node, map: map, text: text, spans: &spans, outline: &outline)
            for child in node.children {
                stack.append(child)
            }
        }

        let frontmatter = MarkdownFrontmatter.range(in: text)
        var normalized = normalize(spans, limit: text.length)
        if let frontmatter {
            normalized.removeAll { $0.intersects(frontmatter) }
            normalized.append(
                MarkdownSyntaxSpan(range: frontmatter, kind: .frontmatter)
            )
            normalized.sort { $0.range.location < $1.range.location }
        }

        return MarkdownParseOutput(
            spans: normalized,
            nodeCount: nodeCount,
            outline: outline.sorted { $0.range.location < $1.range.location },
            lineStarts: map.lineStarts,
            wordCount: TextStatistics.countWords(source),
            characterCount: map.characterCount
        )
    }

    // MARK: - Node emission

    private static func emit(
        _ node: Markup,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan],
        outline: inout [OutlineItem]
    ) {
        switch node {
        case let heading as Heading:
            emitHeading(heading, map: map, text: text, spans: &spans, outline: &outline)

        case let emphasis as Emphasis:
            emitChildDelimiters(emphasis, kind: .emphasisMarker, map: map, text: text, spans: &spans)

        case let strong as Strong:
            emitChildDelimiters(strong, kind: .strongMarker, map: map, text: text, spans: &spans)

        case let strike as Strikethrough:
            emitChildDelimiters(strike, kind: .strikethroughMarker, map: map, text: text, spans: &spans)

        case let code as InlineCode:
            emitInlineCode(code, map: map, text: text, spans: &spans)

        case let codeBlock as CodeBlock:
            emitCodeBlock(codeBlock, map: map, text: text, spans: &spans)

        case let quote as BlockQuote:
            emitLineMarkers(quote, marker: 0x3E, kind: .blockQuoteMarker, map: map, text: text, spans: &spans)

        case let item as ListItem:
            emitListMarker(item, map: map, text: text, spans: &spans)

        case let link as Link:
            emitChildDelimiters(link, kind: .linkPunctuation, map: map, text: text, spans: &spans)

        case let image as Image:
            emitChildDelimiters(image, kind: .imagePunctuation, map: map, text: text, spans: &spans)

        case let rule as ThematicBreak:
            guard let range = clamped(map.nsRange(for: rule.range), text: text) else { return }
            let line = text.lineRange(for: NSRange(location: range.location, length: 0))
            append(trimmedToContent(line, text: text), .thematicBreak, to: &spans, limit: text.length)

        case let html as HTMLBlock:
            guard let range = clamped(map.nsRange(for: html.range), text: text) else { return }
            append(range, .rawHTML, to: &spans, limit: text.length)

        case let html as InlineHTML:
            guard let range = clamped(map.nsRange(for: html.range), text: text) else { return }
            append(range, .rawHTML, to: &spans, limit: text.length)

        default:
            break
        }
    }

    // MARK: - Headings

    private static func emitHeading(
        _ heading: Heading,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan],
        outline: inout [OutlineItem]
    ) {
        guard let range = clamped(map.nsRange(for: heading.range), text: text) else { return }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let lineEnd = min(line.location + line.length, text.length)

        var cursor = line.location
        while cursor < lineEnd, text.character(at: cursor) == 0x23 {
            cursor += 1
        }

        guard cursor > line.location else {
            emitSetextUnderline(range, map: map, text: text, spans: &spans)
            let title = lineText(
                text.lineRange(for: NSRange(location: range.location, length: 0)),
                text: text
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            outline.append(
                OutlineItem(level: setextLevel(in: range, text: text), title: title, range: NSRange(location: line.location, length: 0))
            )
            return
        }

        append(
            NSRange(location: line.location, length: cursor - line.location),
            .headingMarker,
            to: &spans,
            limit: text.length
        )

        var contentEnd = lineEnd
        while contentEnd > cursor, isNewline(text.character(at: contentEnd - 1)) {
            contentEnd -= 1
        }
        var trailingEnd = contentEnd
        while trailingEnd > cursor, isSpaceOrTab(text.character(at: trailingEnd - 1)) {
            trailingEnd -= 1
        }
        var trailingStart = trailingEnd
        while trailingStart > cursor, text.character(at: trailingStart - 1) == 0x23 {
            trailingStart -= 1
        }
        if trailingStart < trailingEnd {
            append(
                NSRange(location: trailingStart, length: trailingEnd - trailingStart),
                .headingMarker,
                to: &spans,
                limit: text.length
            )
        }

        let rawTitle = text.substring(
            with: NSRange(location: cursor, length: max(0, trailingStart - cursor))
        )
        outline.append(
            OutlineItem(
                level: heading.level,
                title: rawTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                range: NSRange(location: line.location, length: 0)
            )
        )
    }

    private static func lineText(_ line: NSRange, text: NSString) -> String {
        var end = min(line.location + line.length, text.length)
        while end > line.location, isNewline(text.character(at: end - 1)) {
            end -= 1
        }
        return text.substring(with: NSRange(location: line.location, length: end - line.location))
    }

    private static func setextLevel(in range: NSRange, text: NSString) -> Int {
        guard range.length > 1 else { return 1 }
        let last = range.location + range.length - 1
        let line = text.lineRange(for: NSRange(location: last, length: 0))
        var cursor = line.location
        while cursor < min(line.location + line.length, text.length),
              isSpaceOrTab(text.character(at: cursor)) {
            cursor += 1
        }
        guard cursor < min(line.location + line.length, text.length) else { return 1 }
        return text.character(at: cursor) == 0x3D ? 1 : 2
    }

    private static func emitSetextUnderline(
        _ headingRange: NSRange,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan]
    ) {
        guard headingRange.length > 1 else { return }
        let lastCharacter = headingRange.location + headingRange.length - 1
        let line = text.lineRange(for: NSRange(location: lastCharacter, length: 0))
        let lineEnd = min(line.location + line.length, text.length)

        var cursor = line.location
        while cursor < lineEnd, isSpaceOrTab(text.character(at: cursor)) {
            cursor += 1
        }
        guard cursor < lineEnd else { return }
        let marker = text.character(at: cursor)
        guard marker == 0x3D || marker == 0x2D else { return }

        var end = cursor
        while end < lineEnd, !isNewline(text.character(at: end)) {
            end += 1
        }
        guard end > cursor + 1 else { return }
        append(
            NSRange(location: cursor, length: end - cursor),
            .headingMarker,
            to: &spans,
            limit: text.length
        )
    }

    // MARK: - Inline and fenced markers

    private static func emitChildDelimiters(
        _ node: Markup,
        kind: MarkdownSyntaxKind,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan]
    ) {
        guard let range = clamped(map.nsRange(for: node.range), text: text) else { return }
        guard node.childCount > 0 else {
            append(range, kind, to: &spans, limit: text.length)
            return
        }

        var firstStart: Int?
        var lastEnd: Int?
        for child in node.children {
            guard let childRange = map.nsRange(for: child.range) else { continue }
            if firstStart == nil {
                firstStart = childRange.location
            }
            lastEnd = childRange.location + childRange.length
        }

        guard let first = firstStart, let last = lastEnd, last >= first else {
            append(range, kind, to: &spans, limit: text.length)
            return
        }

        if first > range.location {
            append(
                NSRange(location: range.location, length: first - range.location),
                kind,
                to: &spans,
                limit: text.length
            )
        }
        let rangeEnd = range.location + range.length
        if last < rangeEnd {
            append(
                NSRange(location: last, length: rangeEnd - last),
                kind,
                to: &spans,
                limit: text.length
            )
        }
    }

    private static func emitInlineCode(
        _ code: InlineCode,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan]
    ) {
        guard let range = clamped(map.nsRange(for: code.range), text: text) else { return }
        let rangeEnd = range.location + range.length
        guard rangeEnd > range.location, text.character(at: range.location) == 0x60 else { return }

        var openEnd = range.location
        while openEnd < rangeEnd, text.character(at: openEnd) == 0x60 {
            openEnd += 1
        }
        append(
            NSRange(location: range.location, length: openEnd - range.location),
            .inlineCodeMarker,
            to: &spans,
            limit: text.length
        )

        var closeStart = rangeEnd
        while closeStart > openEnd, text.character(at: closeStart - 1) == 0x60 {
            closeStart -= 1
        }
        if closeStart < rangeEnd {
            append(
                NSRange(location: closeStart, length: rangeEnd - closeStart),
                .inlineCodeMarker,
                to: &spans,
                limit: text.length
            )
        }
    }

    private static func emitCodeBlock(
        _ block: CodeBlock,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan]
    ) {
        guard let range = clamped(map.nsRange(for: block.range), text: text) else { return }
        let blockEnd = range.location + range.length
        let firstLine = text.lineRange(for: NSRange(location: range.location, length: 0))
        let firstLineEnd = min(firstLine.location + firstLine.length, text.length)

        var cursor = firstLine.location
        var spaces = 0
        while cursor < firstLineEnd, spaces < 4, isSpaceOrTab(text.character(at: cursor)) {
            cursor += 1
            spaces += 1
        }
        guard cursor < firstLineEnd else { return }

        let fence = text.character(at: cursor)
        guard fence == 0x60 || fence == 0x7E else {
            // Indented code: no delimiters to dim yet.
            return
        }

        var openEnd = cursor
        while openEnd < firstLineEnd, text.character(at: openEnd) == fence {
            openEnd += 1
        }
        guard openEnd - cursor >= 3 else { return }

        var openingEnd = firstLineEnd
        while openingEnd > cursor, isNewline(text.character(at: openingEnd - 1)) {
            openingEnd -= 1
        }
        append(
            NSRange(location: cursor, length: openingEnd - cursor),
            .fencedCodeDelimiter,
            to: &spans,
            limit: text.length
        )

        var lastLine: (start: Int, end: Int)?
        var lineStart = firstLineEnd
        while lineStart < blockEnd {
            let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineEnd = min(line.location + line.length, text.length)
            var contentEnd = lineEnd
            while contentEnd > line.location, isNewline(text.character(at: contentEnd - 1)) {
                contentEnd -= 1
            }
            if contentEnd > line.location {
                lastLine = (line.location, contentEnd)
            }
            if lineEnd <= lineStart {
                break
            }
            lineStart = lineEnd
        }

        guard let last = lastLine else { return }
        var closeCursor = last.start
        var closeSpaces = 0
        while closeCursor < last.end, closeSpaces < 4, isSpaceOrTab(text.character(at: closeCursor)) {
            closeCursor += 1
            closeSpaces += 1
        }
        guard closeCursor < last.end, text.character(at: closeCursor) == fence else { return }

        var closeEnd = closeCursor
        while closeEnd < last.end, text.character(at: closeEnd) == fence {
            closeEnd += 1
        }
        guard closeEnd - closeCursor >= openEnd - cursor else { return }
        append(
            NSRange(location: closeCursor, length: closeEnd - closeCursor),
            .fencedCodeDelimiter,
            to: &spans,
            limit: text.length
        )
    }

    // MARK: - Line prefixes and list markers

    private static func emitLineMarkers(
        _ node: Markup,
        marker: unichar,
        kind: MarkdownSyntaxKind,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan]
    ) {
        guard let range = clamped(map.nsRange(for: node.range), text: text) else { return }
        let end = range.location + range.length
        var lineStart = range.location
        while lineStart < end {
            let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineEnd = min(line.location + line.length, text.length)

            var cursor = line.location
            var spaces = 0
            while cursor < lineEnd, spaces < 4, text.character(at: cursor) == 0x20 {
                cursor += 1
                spaces += 1
            }
            if cursor < lineEnd, text.character(at: cursor) == marker {
                var markerEnd = cursor + 1
                if markerEnd < lineEnd, isSpaceOrTab(text.character(at: markerEnd)) {
                    markerEnd += 1
                }
                append(
                    NSRange(location: cursor, length: markerEnd - cursor),
                    kind,
                    to: &spans,
                    limit: text.length
                )
            }

            if lineEnd <= lineStart {
                break
            }
            lineStart = lineEnd
        }
    }

    private static func emitListMarker(
        _ item: ListItem,
        map: SourceMap,
        text: NSString,
        spans: inout [MarkdownSyntaxSpan]
    ) {
        guard let range = clamped(map.nsRange(for: item.range), text: text) else { return }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let lineEnd = min(line.location + line.length, text.length)

        var cursor = line.location
        while cursor < lineEnd, isSpaceOrTab(text.character(at: cursor)) {
            cursor += 1
        }
        guard cursor < lineEnd else { return }

        let first = text.character(at: cursor)
        var markerEnd: Int

        if first == 0x2D || first == 0x2A || first == 0x2B {
            markerEnd = cursor + 1
        } else if isASCIIDigit(first) {
            var digits = cursor
            while digits < lineEnd, isASCIIDigit(text.character(at: digits)) {
                digits += 1
            }
            guard digits < lineEnd else { return }
            let delimiter = text.character(at: digits)
            guard delimiter == 0x2E || delimiter == 0x29 else { return }
            markerEnd = digits + 1
        } else {
            return
        }

        if markerEnd < lineEnd, isSpaceOrTab(text.character(at: markerEnd)) {
            markerEnd += 1
        }
        append(
            NSRange(location: cursor, length: markerEnd - cursor),
            .listMarker,
            to: &spans,
            limit: text.length
        )

        if markerEnd < lineEnd, text.character(at: markerEnd) == 0x5B {
            var close = markerEnd + 1
            var depth = 0
            while close < lineEnd, close <= markerEnd + 2, depth < 3 {
                if text.character(at: close) == 0x5D {
                    append(
                        NSRange(location: markerEnd, length: close - markerEnd + 1),
                        .listMarker,
                        to: &spans,
                        limit: text.length
                    )
                    break
                }
                close += 1
                depth += 1
            }
        }
    }

    // MARK: - Helpers

    private static func append(
        _ range: NSRange,
        _ kind: MarkdownSyntaxKind,
        to spans: inout [MarkdownSyntaxSpan],
        limit: Int
    ) {
        guard range.location >= 0, range.location < limit, range.length > 0 else { return }
        var clampedRange = range
        if clampedRange.location + clampedRange.length > limit {
            clampedRange.length = limit - clampedRange.location
        }
        guard clampedRange.length > 0 else { return }
        spans.append(MarkdownSyntaxSpan(range: clampedRange, kind: kind))
    }

    private static func clamped(_ range: NSRange?, text: NSString) -> NSRange? {
        guard var range else { return nil }
        guard range.location >= 0, range.location <= text.length else { return nil }
        if range.location + range.length > text.length {
            range.length = text.length - range.location
        }
        guard range.length > 0 else { return nil }
        return range
    }

    private static func trimmedToContent(_ line: NSRange, text: NSString) -> NSRange {
        var end = min(line.location + line.length, text.length)
        while end > line.location, isNewline(text.character(at: end - 1)) {
            end -= 1
        }
        return NSRange(location: line.location, length: end - line.location)
    }

    private static func normalize(_ spans: [MarkdownSyntaxSpan], limit: Int) -> [MarkdownSyntaxSpan] {
        guard spans.count > 1 else { return spans }
        let sorted = spans.sorted { left, right in
            if left.range.location != right.range.location {
                return left.range.location < right.range.location
            }
            if left.range.length != right.range.length {
                return left.range.length < right.range.length
            }
            return left.kind.rawValue < right.kind.rawValue
        }

        var result: [MarkdownSyntaxSpan] = []
        result.reserveCapacity(sorted.count)
        for span in sorted {
            guard span.range.location >= 0, span.range.location < limit, span.range.length > 0 else { continue }
            if let previous = result.last,
               previous.range == span.range,
               previous.kind == span.kind {
                continue
            }
            result.append(span)
        }
        return result
    }

    private static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D
    }

    private static func isSpaceOrTab(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    private static func isASCIIDigit(_ character: unichar) -> Bool {
        character >= 0x30 && character <= 0x39
    }
}
