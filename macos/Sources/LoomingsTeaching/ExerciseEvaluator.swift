import Foundation
import LoomingsMarkdown

/// The outcome of one exercise check, ready to show.
public struct CheckResult: Equatable, Sendable {
    public let check: ExerciseCheck
    public let label: String
    public let passed: Bool
    /// What was found, for example "3 of 5 items".
    public let detail: String
}

/// Checks that come with a document from outside it (a bundled lesson).
/// They look only at what follows `after`, the lesson's original text, so the
/// lesson's own examples never count as the student's answer.
public struct AttachedChecks: Equatable, Sendable {
    public let checks: [ExerciseCheck]
    public let after: String?

    public init(checks: [ExerciseCheck], after: String?) {
        self.checks = checks
        self.after = after
    }
}

public enum ExerciseEvaluator {
    public static func evaluate(
        _ source: String,
        attached: AttachedChecks? = nil
    ) -> (results: [CheckResult], notes: [DirectiveNote]) {
        evaluate(ParsedMarkdown(source), attached: attached)
    }

    /// As above, reusing a parse of the whole document for its own checks.
    public static func evaluate(
        _ parsed: ParsedMarkdown,
        attached: AttachedChecks? = nil
    ) -> (results: [CheckResult], notes: [DirectiveNote]) {
        let source = parsed.source
        var checks: [ExerciseCheck] = []
        var notes: [DirectiveNote] = []
        for directive in Directives.read(source) where directive.key == "check" {
            switch ExerciseCheck.parse(directive) {
            case .success(let check): checks.append(check)
            case .failure(let note): notes.append(note)
            }
        }

        var results: [CheckResult] = []
        func needsWords(_ list: [ExerciseCheck]) -> Bool {
            list.contains { if case .words = $0 { return true } else { return false } }
        }
        if !checks.isEmpty {
            let census = Census(parsed, countWords: needsWords(checks))
            results += checks.map { census.result(for: $0) }
        }
        if let attached, !attached.checks.isEmpty {
            let census = Census(ParsedMarkdown(scope(of: source, after: attached.after)), countWords: needsWords(attached.checks))
            results += attached.checks.map { census.result(for: $0) }
        }
        return (results, notes)
    }

    /// The part of `source` that follows the anchor text: everything after it
    /// when the document still starts with it, else after its last line,
    /// else the whole document.
    static func scope(of source: String, after anchor: String?) -> String {
        guard let anchor else { return source }
        let trimmed = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return source }
        if source.hasPrefix(trimmed) {
            return String(source.dropFirst(trimmed.count))
        }
        let lastLine = trimmed.split(separator: "\n").last.map(String.init) ?? trimmed
        let text = source as NSString
        let found = text.range(of: lastLine, options: .backwards)
        if found.location != NSNotFound {
            return text.substring(from: NSMaxRange(found))
        }
        return source
    }
}

/// What a document contains, counted once.
private struct Census {
    var headings: [Int] = []
    var bulletLists: [Int] = []
    var orderedLists: [Int] = []
    var nested = false
    var quotes = 0
    var codeLanguages: [String?] = []
    var inlineCode = 0
    var links = 0
    var referenceLinks = 0
    var imagesWithAlt = 0
    var tableRows: [Int] = []
    var emphasis = 0
    var strong = 0
    var words = 0

    init(_ parsed: ParsedMarkdown, countWords: Bool) {
        let text = parsed.text
        let frontmatter = parsed.frontmatter
        if countWords {
            let body = frontmatter.map { text.substring(from: NSMaxRange($0)) } ?? parsed.source
            words = TextStatistics.countWords(body)
        }

        let map = parsed.map
        let tree = parsed.tree
        withExtendedLifetime(tree) {
            var stack: [(MarkdownNode, Bool)] = []
            // Frontmatter can only be a top-level block, so only those are tested.
            for child in tree.document.children {
                if let frontmatter, let range = map.nsRange(for: child),
                   NSIntersectionRange(range, frontmatter).length > 0 {
                    continue
                }
                stack.append((child, false))
            }
            stack.reverse()
            while let (node, insideItem) = stack.popLast() {
                count(node, insideItem: insideItem, map: map, text: text)
                let childInsideItem = insideItem || node.kind == .item
                for child in node.children {
                    stack.append((child, childInsideItem))
                }
            }
        }
    }

    mutating func count(_ node: MarkdownNode, insideItem: Bool, map: SourceMap, text: NSString) {
        switch node.kind {
        case .heading: headings.append(node.headingLevel)
        case .list:
            let items = node.children.filter { $0.kind == .item }.count
            if node.isOrderedList { orderedLists.append(items) } else { bulletLists.append(items) }
            if insideItem { nested = true }
        case .blockQuote: quotes += 1
        case .codeBlock:
            let first = text.lineRange(for: NSRange(location: map.nsRange(for: node)?.location ?? 0, length: 0))
            let opening = text.substring(with: first).trimmingCharacters(in: .whitespaces)
            let fenced = opening.hasPrefix("```") || opening.hasPrefix("~~~")
            let language = fenced ? node.fenceInfo?.split(separator: " ").first.map { String($0).lowercased() } : nil
            codeLanguages.append(language)
        case .code: inlineCode += 1
        case .link:
            links += 1
            if let range = map.nsRange(for: node), range.length > 0,
               text.character(at: NSMaxRange(range) - 1) == 0x5D { // ]
                referenceLinks += 1
            }
        case .image:
            let alt = node.children.filter { $0.kind == .text }.map(\.literal).joined()
            if !alt.trimmingCharacters(in: .whitespaces).isEmpty { imagesWithAlt += 1 }
        case .table:
            tableRows.append(node.children.filter { $0.kind == .tableRow }.count)
        case .emphasis: emphasis += 1
        case .strong: strong += 1
        default: break
        }
    }

    func result(for check: ExerciseCheck) -> CheckResult {
        func make(_ label: String, _ passed: Bool, _ detail: String) -> CheckResult {
            CheckResult(check: check, label: label, passed: passed, detail: detail)
        }
        func plural(_ count: Int, _ one: String, _ many: String) -> String {
            "\(count) \(count == 1 ? one : many)"
        }
        switch check {
        case .heading(let level, let minimum):
            let found = headings.filter { level == nil || $0 == level }.count
            let kind = level.map { "level-\($0) " } ?? ""
            let label = minimum == 1 ? "A \(kind)heading" : "\(minimum) \(kind)headings"
            return make(label, found >= minimum, "found \(found)")
        case .bulletList(let items):
            let best = bulletLists.max() ?? 0
            return make("A bulleted list of \(plural(items, "item", "items"))", best >= items,
                        bulletLists.isEmpty ? "no bulleted list yet" : "longest has \(plural(best, "item", "items"))")
        case .orderedList(let items):
            let best = orderedLists.max() ?? 0
            return make("A numbered list of \(plural(items, "item", "items"))", best >= items,
                        orderedLists.isEmpty ? "no numbered list yet" : "longest has \(plural(best, "item", "items"))")
        case .nestedList:
            return make("A list inside a list", nested, nested ? "found" : "not yet")
        case .quote:
            return make("A quotation", quotes > 0, quotes > 0 ? "found" : "not yet")
        case .codeBlock(let language):
            let found = language.map { wanted in codeLanguages.contains { $0 == wanted.lowercased() } } ?? !codeLanguages.isEmpty
            return make(language.map { "A \($0) code block" } ?? "A code block", found, found ? "found" : "not yet")
        case .codeLanguage:
            let found = codeLanguages.contains { $0 != nil }
            return make("A code block with its language named", found, found ? "found" : "not yet")
        case .inlineCode(let minimum):
            return make(minimum == 1 ? "Inline code" : "\(minimum) pieces of inline code", inlineCode >= minimum, "found \(inlineCode)")
        case .link(let minimum):
            return make(minimum == 1 ? "A link" : "\(minimum) links", links >= minimum, "found \(links)")
        case .referenceLink:
            return make("A reference link", referenceLinks > 0, referenceLinks > 0 ? "found" : "not yet")
        case .imageAlt:
            return make("An image with alternative text", imagesWithAlt > 0, imagesWithAlt > 0 ? "found" : "not yet")
        case .table(let rows):
            let best = tableRows.max() ?? 0
            return make("A table with \(plural(rows, "row", "rows"))", best >= rows,
                        tableRows.isEmpty ? "no table yet" : "largest has \(plural(best, "row", "rows"))")
        case .emphasis:
            return make("Emphasis", emphasis > 0, emphasis > 0 ? "found" : "not yet")
        case .strong:
            return make("Strong emphasis", strong > 0, strong > 0 ? "found" : "not yet")
        case .words(let minimum):
            return make("At least \(minimum) words", words >= minimum, plural(words, "word", "words"))
        }
    }
}
