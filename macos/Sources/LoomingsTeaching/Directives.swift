import Foundation
import LoomingsMarkdown

/// A teaching instruction in a document's frontmatter, for example
/// `check: ordered-list 3` or `limit: Introduction 200`.
public struct Directive: Equatable, Sendable {
    public let key: String
    public let value: String
    /// 0-based line in the document.
    public let line: Int

    public init(key: String, value: String, line: Int) {
        self.key = key
        self.value = value
        self.line = line
    }
}

/// A directive that could not be understood, shown to the writer instead of
/// being dropped silently.
public struct DirectiveNote: Equatable, Sendable, Error {
    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public enum Directives {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(check|limit)\s*:\s*(.*?)\s*$"#,
        options: [.caseInsensitive]
    )

    /// The `check` and `limit` lines of the leading frontmatter, in order.
    public static func read(_ source: String) -> [Directive] {
        let text = source as NSString
        guard let frontmatter = MarkdownFrontmatter.range(in: text) else { return [] }
        var directives: [Directive] = []
        var lineNumber = 0
        text.enumerateSubstrings(in: frontmatter, options: [.byLines]) { line, _, _, _ in
            defer { lineNumber += 1 }
            guard let line, lineNumber > 0 else { return }
            let range = NSRange(location: 0, length: (line as NSString).length)
            guard let match = pattern.firstMatch(in: line, range: range) else { return }
            let key = (line as NSString).substring(with: match.range(at: 1)).lowercased()
            let value = (line as NSString).substring(with: match.range(at: 2))
            directives.append(Directive(key: key, value: value, line: lineNumber))
        }
        return directives
    }
}

/// One self-check of an exercise.
public enum ExerciseCheck: Equatable, Sendable {
    case heading(level: Int?, min: Int)
    case bulletList(items: Int)
    case orderedList(items: Int)
    case nestedList
    case quote
    case codeBlock(language: String?)
    /// A fenced code block with any language name after the fence.
    case codeLanguage
    case inlineCode(min: Int)
    case link(min: Int)
    case referenceLink
    case imageAlt
    case table(rows: Int)
    case emphasis
    case strong
    case words(min: Int)

    public static func parse(_ directive: Directive) -> Result<ExerciseCheck, DirectiveNote> {
        let parts = directive.value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let kind = parts.first?.lowercased() else {
            return .failure(note(directive, "A check needs a kind, for example \"check: heading\"."))
        }
        let arguments = Array(parts.dropFirst())

        func number(_ index: Int, default fallback: Int?) -> Int?? {
            guard index < arguments.count else { return .some(fallback) }
            guard let value = Int(arguments[index]), value > 0 else { return .none }
            return .some(value)
        }
        func noArguments(_ check: ExerciseCheck) -> Result<ExerciseCheck, DirectiveNote> {
            arguments.isEmpty ? .success(check) : .failure(note(directive, "\"\(kind)\" takes no number."))
        }
        func counted(_ make: (Int) -> ExerciseCheck, default fallback: Int) -> Result<ExerciseCheck, DirectiveNote> {
            guard arguments.count <= 1, case .some(.some(let value)) = number(0, default: fallback) else {
                return .failure(note(directive, "\"\(kind)\" takes one whole number, for example \"\(kind) \(fallback)\"."))
            }
            return .success(make(value))
        }

        switch kind {
        case "heading":
            guard arguments.count <= 2,
                  case .some(let level) = number(0, default: nil),
                  case .some(.some(let minimum)) = number(1, default: 1) else {
                return .failure(note(directive, "\"heading\" takes a level from 1 to 6 and a count, for example \"heading 2\"."))
            }
            if let level, !(1...6).contains(level) {
                return .failure(note(directive, "A heading level runs from 1 to 6."))
            }
            return .success(.heading(level: level, min: minimum))
        case "bullet-list": return counted({ .bulletList(items: $0) }, default: 2)
        case "ordered-list": return counted({ .orderedList(items: $0) }, default: 2)
        case "inline-code": return counted({ .inlineCode(min: $0) }, default: 1)
        case "link": return counted({ .link(min: $0) }, default: 1)
        case "table": return counted({ .table(rows: $0) }, default: 1)
        case "words":
            guard arguments.count == 1, let value = Int(arguments[0]), value > 0 else {
                return .failure(note(directive, "\"words\" needs the least number of words, for example \"words 50\"."))
            }
            return .success(.words(min: value))
        case "code-block":
            guard arguments.count <= 1 else {
                return .failure(note(directive, "\"code-block\" takes one language name at most."))
            }
            return .success(.codeBlock(language: arguments.first))
        case "code-language": return noArguments(.codeLanguage)
        case "nested-list": return noArguments(.nestedList)
        case "quote": return noArguments(.quote)
        case "reference-link": return noArguments(.referenceLink)
        case "image-alt": return noArguments(.imageAlt)
        case "emphasis": return noArguments(.emphasis)
        case "strong": return noArguments(.strong)
        default:
            return .failure(note(directive, "Unknown check \"\(parts[0])\"."))
        }
    }
}

/// A word limit for one section, matched to a heading by its title.
public struct SectionLimit: Equatable, Sendable {
    public let heading: String
    public let maxWords: Int

    public init(heading: String, maxWords: Int) {
        self.heading = heading
        self.maxWords = maxWords
    }

    public static func parse(_ directive: Directive) -> Result<SectionLimit, DirectiveNote> {
        let parts = directive.value.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2, let last = parts.last, let value = Int(last), value > 0 else {
            return .failure(note(directive, "A limit needs a heading and a number, for example \"limit: Introduction 200\"."))
        }
        let heading = parts.dropLast().joined(separator: " ")
        return .success(SectionLimit(heading: heading, maxWords: value))
    }
}

private func note(_ directive: Directive, _ message: String) -> DirectiveNote {
    DirectiveNote(line: directive.line, message: message)
}
