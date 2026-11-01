import Foundation
import LoomingsMarkdown

/// What a Markdown marker does, for the option-click explanation.
public struct MarkerExplanation: Equatable, Sendable {
    public let title: String
    public let body: String
    /// The bundled lesson that teaches it, for example "02-lists-quotes.md".
    public let lesson: String?

    public init(title: String, body: String, lesson: String?) {
        self.title = title
        self.body = body
        self.lesson = lesson
    }
}

public enum MarkerGlossary {
    public static func explain(kind: MarkdownSyntaxKind, marker: String) -> MarkerExplanation? {
        let mark = marker.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .headingMarker:
            if mark.first == "=" {
                return MarkerExplanation(
                    title: "Level-1 heading (underline)",
                    body: "A line of = signs under text makes that text a level-1 heading. A line of hyphens makes a level-2 heading.",
                    lesson: "01-basics.md"
                )
            }
            if mark.first == "-" {
                return MarkerExplanation(
                    title: "Level-2 heading (underline)",
                    body: "A line of hyphens directly under text makes that text a level-2 heading. For a horizontal rule, leave a blank line above the hyphens.",
                    lesson: "01-basics.md"
                )
            }
            let level = min(6, max(1, mark.filter { $0 == "#" }.count))
            let signs = level == 1 ? "One # sign" : "\(level) # signs"
            return MarkerExplanation(
                title: "Level-\(level) heading",
                body: "\(signs) and a space start a level-\(level) heading. One # is the title of the document, two a section, three a subsection.",
                lesson: "01-basics.md"
            )
        case .emphasisMarker:
            return MarkerExplanation(
                title: "Emphasis",
                body: "One * or _ on each side of a word sets it in italics.",
                lesson: "01-basics.md"
            )
        case .strongMarker:
            return MarkerExplanation(
                title: "Strong emphasis",
                body: "Two * or _ on each side of a word set it in bold.",
                lesson: "01-basics.md"
            )
        case .strikethroughMarker:
            return MarkerExplanation(
                title: "Strikethrough",
                body: "Two ~ on each side of a word draw a line through it.",
                lesson: nil
            )
        case .inlineCodeMarker:
            return MarkerExplanation(
                title: "Inline code",
                body: "Backticks show the text between them exactly as typed, in a code face. Markdown inside them is not read.",
                lesson: "04-code.md"
            )
        case .fencedCodeDelimiter:
            return MarkerExplanation(
                title: "Code block fence",
                body: "A line of three backticks or tildes opens a code block and another closes it. A language name may follow the opening fence.",
                lesson: "04-code.md"
            )
        case .blockQuoteMarker:
            return MarkerExplanation(
                title: "Quotation",
                body: "A > at the start of a line quotes the text after it. Quotations can hold several paragraphs.",
                lesson: "02-lists-quotes.md"
            )
        case .listMarker:
            if mark.hasPrefix("[") {
                return MarkerExplanation(
                    title: "Task box",
                    body: "[ ] after a list marker is an open task; [x] is a finished one.",
                    lesson: "02-lists-quotes.md"
                )
            }
            if mark.first?.isNumber == true {
                return MarkerExplanation(
                    title: "Numbered list item",
                    body: "A number, a full stop or bracket, and a space start a numbered item. The numbers need not be in order; the result counts on from the first.",
                    lesson: "02-lists-quotes.md"
                )
            }
            return MarkerExplanation(
                title: "Bullet list item",
                body: "A hyphen, asterisk or plus sign and a space start a bullet item. Indent an item to put it inside the one above.",
                lesson: "02-lists-quotes.md"
            )
        case .linkPunctuation:
            return MarkerExplanation(
                title: "Link",
                body: "Square brackets hold the text to show; the parentheses after them hold the address.",
                lesson: "03-links-images.md"
            )
        case .imagePunctuation:
            return MarkerExplanation(
                title: "Image",
                body: "Like a link with ! in front. The brackets hold the alternative text that describes the image.",
                lesson: "03-links-images.md"
            )
        case .thematicBreak:
            return MarkerExplanation(
                title: "Horizontal rule",
                body: "Three or more hyphens, asterisks or underscores on a line of their own draw a rule across the page.",
                lesson: "05-tables-rules.md"
            )
        case .rawHTML:
            return MarkerExplanation(
                title: "HTML",
                body: "Loomings shows HTML as written. The preview never runs it.",
                lesson: nil
            )
        case .frontmatter:
            return MarkerExplanation(
                title: "Frontmatter",
                body: "The block between two lines of --- at the very top holds facts about the document, such as its title. It is not shown in the result.",
                lesson: "06-frontmatter.md"
            )
        case .codeBlockContent:
            return nil
        }
    }
}
