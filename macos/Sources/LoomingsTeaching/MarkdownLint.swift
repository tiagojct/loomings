import Foundation
import LoomingsMarkdown

/// A one-click repair: replace `range` (UTF-16) with `replacement`.
public struct LintFix: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let title: String

    public init(range: NSRange, replacement: String, title: String) {
        self.range = range
        self.replacement = replacement
        self.title = title
    }
}

/// A gentle note about a common Markdown mistake.
public struct LintIssue: Equatable, Sendable {
    public let rule: String
    public let range: NSRange
    public let message: String
    public let fix: LintFix?

    public init(rule: String, range: NSRange, message: String, fix: LintFix?) {
        self.rule = rule
        self.range = range
        self.message = message
        self.fix = fix
    }
}

/// The learner's checker. Rule ids and wording are shared with the web port
/// through `Tests/LoomingsTeachingTests/Fixtures/lint-cases.json`.
public enum MarkdownLint {
    public static func lint(_ source: String) -> [LintIssue] {
        guard !source.isEmpty else { return [] }
        return lint(ParsedMarkdown(source))
    }

    public static func lint(_ parsed: ParsedMarkdown) -> [LintIssue] {
        guard parsed.text.length > 0 else { return [] }
        let tree = parsed.tree
        var context = Context(text: parsed.text, map: parsed.map)
        context.frontmatter = parsed.frontmatter

        withExtendedLifetime(tree) {
            // Each node travels with the range of its nearest paragraph or
            // heading: cmark gives no position to text on a lazy line.
            var stack: [(MarkdownNode, NSRange?)] = [(tree.document, nil)]
            while let (node, block) = stack.popLast() {
                context.visit(node, block: block)
                let inner = (node.kind == .paragraph || node.kind == .heading) ? context.map.nsRange(for: node) : block
                // Pushed last-first so they are visited in document order.
                var children: [MarkdownNode] = []
                var child = node.firstChild
                while let current = child {
                    children.append(current)
                    child = current.nextSibling
                }
                stack.append(contentsOf: children.reversed().map { ($0, inner) })
            }
        }
        context.checkParagraphs()
        return context.issues.sorted { $0.range.location < $1.range.location }
    }

    static let messages: [String: String] = [
        "heading-space": "A heading needs a space after its # signs; without one this line stays a paragraph.",
        "accidental-setext": "A line of hyphens under text turns that text into a heading. For a horizontal rule, leave a blank line above the hyphens.",
        "unclosed-fence": "This code block is never closed, so everything after it is code. End it with a line of the same fence.",
        "ordered-list-interrupt": "A numbered list that does not start at 1 cannot begin in the middle of a paragraph. Leave a blank line above it.",
        "link-space": "A link address cannot contain spaces unless it is wrapped in < and >.",
        "image-alt": "This image has no alternative text. Describe it between the square brackets for readers who cannot see it.",
        "unpaired-emphasis": "These marks did not pair up, so they show as written. Close them with the same marks after the text.",
        "table-separator": "A table needs a separator row of hyphens under its first row, like | --- | --- |.",
    ]
}

private struct Context {
    let text: NSString
    let map: SourceMap
    var issues: [LintIssue] = []
    /// Paragraphs that start at the beginning of a line (not inside a list
    /// item or a quotation), whose lines can be read as written.
    var paragraphs: [NSRange] = []
    var codeSpans: [NSRange] = []
    /// Source places already given to a text or image node, so the
    /// nearest-match fallback never gives one place to two nodes.
    var claimed: [NSRange] = []

    func isClaimed(_ range: NSRange) -> Bool {
        claimed.contains { NSIntersectionRange($0, range).length > 0 || $0.location == range.location }
    }
    /// cmark reads frontmatter as a paragraph or setext heading; it is
    /// metadata, so it is never checked.
    var frontmatter: NSRange?

    /// The document's own line ending, so fixes keep CRLF files CRLF.
    let lineEnding: String
    /// Just past the last character that is not white space.
    let contentEnd: Int

    init(text: NSString, map: SourceMap) {
        self.text = text
        self.map = map
        self.lineEnding = text.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
        var end = text.length
        while end > 0, let scalar = UnicodeScalar(text.character(at: end - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            end -= 1
        }
        self.contentEnd = end
    }

    mutating func add(_ rule: String, _ range: NSRange, fix: LintFix? = nil) {
        issues.append(LintIssue(rule: rule, range: range, message: MarkdownLint.messages[rule] ?? "", fix: fix))
    }

    mutating func visit(_ node: MarkdownNode, block: NSRange?) {
        let kind = node.kind
        switch kind {
        case .paragraph, .code, .heading, .codeBlock, .image:
            break
        case .text where node.literalContains("**") || node.literalContains("__"):
            break
        default:
            return
        }
        guard let range = sourceRange(of: node, kind: kind, in: block) else { return }
        if let frontmatter, NSIntersectionRange(frontmatter, range).length > 0 { return }
        switch kind {
        case .paragraph:
            if startsLine(range) { paragraphs.append(range) }
        case .code:
            codeSpans.append(range)
        case .heading:
            checkSetext(node, range)
        case .codeBlock:
            checkFence(range)
        case .image:
            let alt = node.children.filter { $0.kind == .text }.map(\.literal).joined()
            if alt.trimmingCharacters(in: .whitespaces).isEmpty {
                add("image-alt", range)
            }
        case .text:
            checkUnpaired(node, range)
        default:
            break
        }
    }

    // MARK: Blocks

    /// Setext headings made with hyphens, when the text reads like prose.
    mutating func checkSetext(_ node: MarkdownNode, _ range: NSRange) {
        let first = lineRange(at: range.location)
        if lineText(first).trimmingCharacters(in: .whitespaces).hasPrefix("#") { return }
        // cmark's range for a setext heading can run on past its underline,
        // so the underline is the first line after the text made only of the
        // marks.
        guard let lastLine = setextUnderline(after: first, before: NSMaxRange(range)) else { return }
        let underline = lineText(lastLine).trimmingCharacters(in: .whitespaces)
        guard underline.first == "-" else { return }
        let content = text.substring(with: NSRange(location: first.location, length: lastLine.location - first.location))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "\r\n" is one Character, so look at scalars.
        let multiline = content.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
        let prose = content.last.map { ".,;:".contains($0) } ?? false
        guard multiline || prose else { return }
        add("accidental-setext", range, fix: LintFix(
            range: NSRange(location: lastLine.location, length: 0),
            replacement: newline(),
            title: "Add a blank line above"
        ))
    }

    /// The first line after `first`, up to `limit`, that is a setext
    /// underline: up to three spaces, then only = or only -.
    func setextUnderline(after first: NSRange, before limit: Int) -> NSRange? {
        var cursor = NSMaxRange(first)
        while cursor < min(limit, text.length) {
            let line = lineRange(at: cursor)
            let content = lineText(line)
            let indent = content.prefix { $0 == " " }.count
            let marks = content.dropFirst(indent).trimmingCharacters(in: .whitespaces)
            if indent <= 3, !marks.isEmpty, marks.allSatisfy({ $0 == "=" }) || marks.allSatisfy({ $0 == "-" }) {
                return line
            }
            guard NSMaxRange(line) > cursor else { break }
            cursor = NSMaxRange(line)
        }
        return nil
    }

    /// A fenced block that runs to the end of the document with no closing fence.
    mutating func checkFence(_ range: NSRange) {
        let first = lineRange(at: range.location)
        let opening = lineText(first)
        let indent = opening.prefix { $0 == " " }.count
        let trimmed = opening.dropFirst(indent)
        guard indent <= 3, let fenceCharacter = trimmed.first, fenceCharacter == "`" || fenceCharacter == "~" else { return }
        let fence = String(trimmed.prefix { $0 == fenceCharacter })
        guard fence.count >= 3 else { return }

        let end = NSMaxRange(range)
        guard end >= contentEnd else { return }

        let lastLine = lineRange(at: max(range.location, end - 1))
        if lastLine.location > first.location {
            let closing = lineText(lastLine).trimmingCharacters(in: .whitespaces)
            if closing.count >= fence.count, closing.allSatisfy({ $0 == fenceCharacter }) { return }
        }

        let fix: LintFix?
        if indent == 0 {
            let ending = text.hasSuffix("\n") ? "" : newline()
            fix = LintFix(
                range: NSRange(location: text.length, length: 0),
                replacement: ending + fence + newline(),
                title: "Close the code block"
            )
        } else {
            fix = nil
        }
        add("unclosed-fence", NSRange(location: first.location, length: (opening as NSString).length), fix: fix)
    }

    // MARK: Inline

    /// Where a node is in the source. cmark's inline positions are off by
    /// a character or two after a tab or on a lazy line, or missing there, so
    /// a text or image position is checked against the source and, when the
    /// text is not there, the nearest match in its paragraph is taken.
    mutating func sourceRange(of node: MarkdownNode, kind: MarkdownNodeKind, in block: NSRange?) -> NSRange? {
        let found = locateNode(node, kind: kind, in: block)
        if let found, kind == .text || kind == .image { claimed.append(found) }
        return found
    }

    func locateNode(_ node: MarkdownNode, kind: MarkdownNodeKind, in block: NSRange?) -> NSRange? {
        let reported = map.nsRange(for: node)
        switch kind {
        case .text:
            let literal = node.literal
            if let reported, !isClaimed(reported), text.substring(with: reported).contains(literal) { return reported }
            return nearest(literal, in: block, near: reported?.location) ?? reported
        case .image:
            if let reported, !isClaimed(reported),
               text.substring(with: reported).hasPrefix("!["), text.substring(with: reported).hasSuffix(")") {
                return reported
            }
            guard let start = nearest("![", in: block, near: reported?.location) else { return reported }
            let destination = text.range(of: "](", options: .literal, range: NSRange(location: start.location, length: NSMaxRange(block ?? start) - start.location))
            guard destination.location != NSNotFound else { return reported }
            let close = text.range(of: ")", options: .literal, range: NSRange(location: NSMaxRange(destination), length: NSMaxRange(block ?? destination) - NSMaxRange(destination)))
            guard close.location != NSNotFound else { return reported }
            return NSRange(location: start.location, length: NSMaxRange(close) - start.location)
        default:
            return reported
        }
    }

    /// The occurrence of `needle` in `block` nearest to `location` (the
    /// first when there is no location).
    func nearest(_ needle: String, in block: NSRange?, near location: Int?) -> NSRange? {
        guard let block, !needle.isEmpty, NSMaxRange(block) <= text.length else { return nil }
        var best: NSRange?
        var search = block
        while search.length > 0 {
            let found = text.range(of: needle, options: .literal, range: search)
            guard found.location != NSNotFound else { break }
            if isClaimed(found) {
                let next = found.location + 1
                search = NSRange(location: next, length: NSMaxRange(block) - next)
                continue
            }
            guard let location else { return found }
            if best.map({ abs($0.location - location) > abs(found.location - location) }) ?? true { best = found }
            let next = found.location + 1
            search = NSRange(location: next, length: NSMaxRange(block) - next)
        }
        return best
    }

    /// Leftover `**` or `__` in a text node, one note for each run of marks.
    /// Only marks written as such count: an escaped mark (`\*`) is meant to
    /// show, though a mark after an escaped backslash (`\\**`) is not escaped.
    mutating func checkUnpaired(_ node: MarkdownNode, _ range: NSRange) {
        let source = text.substring(with: range) as NSString
        var found: [Int] = []
        for marker in [0x2A, 0x5F] as [unichar] { // * _
            var index = 0
            while index < source.length {
                guard source.character(at: index) == marker else { index += 1; continue }
                var backslashes = 0
                while index - backslashes - 1 >= 0, source.character(at: index - backslashes - 1) == 0x5C { backslashes += 1 }
                if backslashes % 2 == 1 { index += 1; continue }
                var end = index
                while end < source.length, source.character(at: end) == marker { end += 1 }
                if end - index >= 2 { found.append(index) }
                index = end
            }
        }
        for location in found.sorted() {
            add("unpaired-emphasis", NSRange(location: range.location + location, length: 2))
        }
    }

    // MARK: Paragraph lines

    mutating func checkParagraphs() {
        for paragraph in paragraphs {
            let lines = linesOf(paragraph)
            for line in lines where firstNonSpace(line) == 0x23 { // #
                checkHeadingSpace([line])
            }
            if lines.count > 1, lines.dropFirst().contains(where: { isDigit(firstNonSpace($0)) }) {
                checkOrderedInterrupt(lines)
            }
            if lines.count > 1, firstNonSpace(lines[0]) == 0x7C { // |
                checkTable(lines)
            }
            if text.range(of: "](", options: .literal, range: paragraph).location != NSNotFound {
                checkLinkSpaces(paragraph)
            }
        }
    }

    /// The first character after up to three spaces, or 0.
    func firstNonSpace(_ line: NSRange) -> unichar {
        var index = line.location
        let end = min(NSMaxRange(line), line.location + 4)
        while index < end {
            let character = text.character(at: index)
            if character != 0x20 { return character }
            index += 1
        }
        return 0
    }

    func isDigit(_ character: unichar) -> Bool {
        character >= 0x30 && character <= 0x39
    }

    mutating func checkHeadingSpace(_ lines: [NSRange]) {
        for line in lines {
            let content = lineText(line)
            let indent = content.prefix { $0 == " " }.count
            guard indent <= 3 else { continue }
            let body = content.dropFirst(indent)
            let hashes = body.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), let next = body.dropFirst(hashes).first,
                  next != " ", next != "\t" else { continue }
            let insertAt = line.location + indent + hashes
            add("heading-space", NSRange(location: line.location, length: (content as NSString).length), fix: LintFix(
                range: NSRange(location: insertAt, length: 0),
                replacement: " ",
                title: "Add a space"
            ))
        }
    }

    private static let orderedMarker = try! NSRegularExpression(pattern: #"^ {0,3}(\d{1,9})[.)][ \t]+\S"#)

    mutating func checkOrderedInterrupt(_ lines: [NSRange]) {
        for line in lines.dropFirst() {
            let content = lineText(line)
            let ns = content as NSString
            guard let match = Self.orderedMarker.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)),
                  let number = Int(ns.substring(with: match.range(at: 1))), number != 1 else { continue }
            add("ordered-list-interrupt", NSRange(location: line.location, length: ns.length), fix: LintFix(
                range: NSRange(location: line.location, length: 0),
                replacement: newline(),
                title: "Add a blank line above"
            ))
            return
        }
    }

    mutating func checkTable(_ lines: [NSRange]) {
        guard lines.count >= 2 else { return }
        let first = lineText(lines[0]).trimmingCharacters(in: .whitespaces)
        let second = lineText(lines[1]).trimmingCharacters(in: .whitespaces)
        guard first.count > 1, second.count > 1,
              first.hasPrefix("|"), first.hasSuffix("|"), second.hasPrefix("|"), second.hasSuffix("|") else { return }
        let columns = first.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false).count
        guard columns >= 1 else { return }
        let row = "|" + String(repeating: " --- |", count: columns) + newline()
        let firstRange = lines[0]
        let afterFirst = lineRange(at: firstRange.location)
        add("table-separator", firstRange, fix: LintFix(
            range: NSRange(location: NSMaxRange(afterFirst), length: 0),
            replacement: row,
            title: "Add the separator row"
        ))
    }

    private static let spacedLink = try! NSRegularExpression(
        pattern: #"\[[^\]\n]+\]\(([^)\s<>"']+(?:[ \t]+[^)\s<>"']+)+)\)"#
    )

    mutating func checkLinkSpaces(_ paragraph: NSRange) {
        let source = text.substring(with: paragraph)
        for match in Self.spacedLink.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length)) {
            let whole = NSRange(location: paragraph.location + match.range.location, length: match.range.length)
            if codeSpans.contains(where: { NSIntersectionRange($0, whole).length > 0 }) { continue }
            let address = NSRange(location: paragraph.location + match.range(at: 1).location, length: match.range(at: 1).length)
            add("link-space", whole, fix: LintFix(
                range: address,
                replacement: "<" + text.substring(with: address) + ">",
                title: "Wrap the address in < >"
            ))
        }
    }

    // MARK: Helpers

    func newline() -> String { lineEnding }

    func startsLine(_ range: NSRange) -> Bool {
        var index = range.location
        var spaces = 0
        while index > 0 {
            let character = text.character(at: index - 1)
            if character == 0x0A || character == 0x0D { return true }
            guard character == 0x20, spaces < 3 else { return false }
            spaces += 1
            index -= 1
        }
        return true
    }

    /// Line ranges (without terminators) covering `range`.
    func linesOf(_ range: NSRange) -> [NSRange] {
        var lines: [NSRange] = []
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end {
            let line = lineRange(at: cursor)
            lines.append(NSRange(location: line.location, length: (lineText(line) as NSString).length))
            let next = NSMaxRange(line)
            guard next > cursor else { break }
            cursor = next
        }
        return lines
    }

    /// The line holding `location`, its terminator included. Lines end at
    /// LF, CRLF or CR, as cmark reads them (NSString would also end them at
    /// U+2028, U+2029 and U+0085, which cmark does not).
    func lineRange(at location: Int) -> NSRange {
        let length = text.length
        var position = min(max(0, location), length)
        // The LF of a CRLF belongs to the line the pair ends.
        if position > 0, position < length, text.character(at: position) == 0x0A, text.character(at: position - 1) == 0x0D {
            position -= 1
        }
        var start = position
        while start > 0 {
            let previous = text.character(at: start - 1)
            if previous == 0x0A || previous == 0x0D { break }
            start -= 1
        }
        var end = position
        while end < length {
            let character = text.character(at: end)
            if character == 0x0A { return NSRange(location: start, length: end + 1 - start) }
            if character == 0x0D {
                let width = end + 1 < length && text.character(at: end + 1) == 0x0A ? 2 : 1
                return NSRange(location: start, length: end + width - start)
            }
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    func lineText(_ line: NSRange) -> String {
        var end = min(NSMaxRange(line), text.length)
        while end > line.location {
            let character = text.character(at: end - 1)
            guard character == 0x0A || character == 0x0D else { break }
            end -= 1
        }
        return text.substring(with: NSRange(location: line.location, length: end - line.location))
    }
}
