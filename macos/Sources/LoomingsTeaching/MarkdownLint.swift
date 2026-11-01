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
        let text = source as NSString
        let map = SourceMap(source)
        let tree = MarkdownTree(parsing: source)
        var context = Context(text: text, map: map)
        context.frontmatter = MarkdownFrontmatter.range(in: text)

        withExtendedLifetime(tree) {
            var stack: [MarkdownNode] = [tree.document]
            while let node = stack.popLast() {
                context.visit(node)
                var child = node.firstChild
                while let current = child {
                    stack.append(current)
                    child = current.nextSibling
                }
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

    mutating func visit(_ node: MarkdownNode) {
        let kind = node.kind
        switch kind {
        case .paragraph, .code, .heading, .codeBlock, .image:
            break
        case .text where node.literalContains("**") || node.literalContains("__"):
            break
        default:
            return
        }
        guard let range = map.nsRange(for: node) else { return }
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
        let first = text.lineRange(for: NSRange(location: range.location, length: 0))
        if lineText(first).trimmingCharacters(in: .whitespaces).hasPrefix("#") { return }
        let lastLine = text.lineRange(for: NSRange(location: max(range.location, NSMaxRange(range) - 1), length: 0))
        let underline = lineText(lastLine).trimmingCharacters(in: .whitespaces)
        guard underline.first == "-", lastLine.location > first.location else { return }
        let content = text.substring(with: NSRange(location: first.location, length: lastLine.location - first.location))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let multiline = content.contains("\n")
        let prose = content.last.map { ".,;:".contains($0) } ?? false
        guard multiline || prose else { return }
        add("accidental-setext", range, fix: LintFix(
            range: NSRange(location: lastLine.location, length: 0),
            replacement: newline(),
            title: "Add a blank line above"
        ))
    }

    /// A fenced block that runs to the end of the document with no closing fence.
    mutating func checkFence(_ range: NSRange) {
        let first = text.lineRange(for: NSRange(location: range.location, length: 0))
        let opening = lineText(first)
        let indent = opening.prefix { $0 == " " }.count
        let trimmed = opening.dropFirst(indent)
        guard indent <= 3, let fenceCharacter = trimmed.first, fenceCharacter == "`" || fenceCharacter == "~" else { return }
        let fence = String(trimmed.prefix { $0 == fenceCharacter })
        guard fence.count >= 3 else { return }

        let end = NSMaxRange(range)
        guard end >= contentEnd else { return }

        let lastLine = text.lineRange(for: NSRange(location: max(range.location, end - 1), length: 0))
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

    mutating func checkUnpaired(_ node: MarkdownNode, _ range: NSRange) {
        let source = text.substring(with: range) as NSString
        var found = source.range(of: "**")
        if found.location == NSNotFound { found = source.range(of: "__") }
        let location = found.location == NSNotFound ? range.location : range.location + found.location
        add("unpaired-emphasis", NSRange(location: location, length: 2))
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
        let afterFirst = text.lineRange(for: NSRange(location: firstRange.location, length: 0))
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
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            lines.append(NSRange(location: line.location, length: (lineText(line) as NSString).length))
            let next = NSMaxRange(line)
            guard next > cursor else { break }
            cursor = next
        }
        return lines
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
