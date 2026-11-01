import Foundation
import Testing
@testable import LoomingsMarkdown

@Suite("Markdown parsing")
struct MarkdownParserTests {
    @Test("UTF-8 columns become UTF-16 offsets")
    func utf8ColumnsBecomeUTF16Offsets() {
        let source = "é *x*"
        let output = MarkdownParser.parse(source)
        let emphasis = output.spans.filter { $0.kind == .emphasisMarker }
        #expect(emphasis.map(\.range) == [
            NSRange(location: 2, length: 1),
            NSRange(location: 4, length: 1),
        ])
    }

    @Test("Emoji before markers do not shift ranges")
    func emojiBeforeMarkersDoesNotShiftRanges() {
        let source = "🌊 *sea*"
        let output = MarkdownParser.parse(source)
        let emphasis = output.spans.filter { $0.kind == .emphasisMarker }
        #expect(emphasis.map(\.range) == [
            NSRange(location: 3, length: 1),
            NSRange(location: 7, length: 1),
        ])
    }

    @Test("Every range stays inside the document")
    func allRangesStayInsideTheDocument() {
        let source = """
        # Heading 🌊

        Some *emphasis*, **strong**, ~~strike~~ and `code`.

        - item one
        - item two

        > quote

        ```swift
        let value = 1
        ```

        [link](https://example.com) and ![image](a.png)

        ---
        """
        let length = (source as NSString).length
        let output = MarkdownParser.parse(source)

        #expect(!output.spans.isEmpty)
        #expect(output.nodeCount > 10)
        for span in output.spans {
            #expect(span.range.location >= 0, "\(span)")
            #expect(span.range.length > 0, "\(span)")
            #expect(
                span.range.location + span.range.length <= length,
                "\(span) escapes \(length)"
            )
        }
    }

    @Test("Fenced code delimiters and info string")
    func fencedCodeDelimitersAndInfoString() {
        let source = "```swift\nlet x = 1\n```\n"
        let output = MarkdownParser.parse(source)
        let fences = output.spans.filter { $0.kind == .fencedCodeDelimiter }
        #expect(fences.count == 2)
        #expect(fences.contains { $0.range == NSRange(location: 0, length: 8) }, "\(fences)")
        #expect(fences.contains { $0.range == NSRange(location: 19, length: 3) }, "\(fences)")
    }

    @Test("Block quote and list markers")
    func lineMarkers() {
        let source = "> quote\n\n- item\n\n1. ordered\n"
        let output = MarkdownParser.parse(source)
        let quotes = output.spans.filter { $0.kind == .blockQuoteMarker }
        let lists = output.spans.filter { $0.kind == .listMarker }

        #expect(quotes.map(\.range) == [NSRange(location: 0, length: 2)])
        #expect(lists.contains { $0.range == NSRange(location: 9, length: 2) })
        #expect(lists.contains { $0.range == NSRange(location: 17, length: 3) })
    }

    @Test("Link punctuation leaves the text alone")
    func linkPunctuationLeavesTheTextAlone() {
        let source = "[text](https://example.com)"
        let output = MarkdownParser.parse(source)
        let punctuation = output.spans.filter { $0.kind == .linkPunctuation }
        #expect(punctuation.map(\.range) == [
            NSRange(location: 0, length: 1),
            NSRange(location: 5, length: 22),
        ])
    }

    @Test("Setext underline")
    func setextUnderline() {
        let source = "Title\n=====\n"
        let output = MarkdownParser.parse(source)
        let markers = output.spans.filter { $0.kind == .headingMarker }
        #expect(markers.map(\.range) == [NSRange(location: 6, length: 5)])
    }

    @Test("Empty and whitespace sources produce no spans")
    func emptySourcesProduceNoSpans() {
        #expect(MarkdownParser.parse("").spans.isEmpty)
        #expect(MarkdownParser.parse("   \n\n").spans.isEmpty)
    }

    @Test("Span ranges are not duplicated")
    func spanRangesAreNotDuplicated() {
        let source = "**bold**"
        let output = MarkdownParser.parse(source)
        let keys = output.spans.map { "\($0.range.location):\($0.range.length):\($0.kind.rawValue)" }
        #expect(keys.count == Set(keys).count)
    }

    @Test("A large pasted paragraph parses in linear time")
    func largePasteParsesInLinearTime() {
        let source = "# Large\n\n" + String(
            repeating: "A pasted line, with a *marker* and `code`.\n",
            count: 4_000
        )
        let clock = ContinuousClock()
        let start = clock.now
        let output = MarkdownParser.parse(source)
        let elapsed = clock.now - start

        #expect(output.spans.count > 1_000)
        #expect(elapsed < .seconds(5), "parse took \(elapsed)")
    }
}

@Suite("Outline, frontmatter and statistics")
struct DocumentAnalysisTests {
    @Test("Outline contains ATX and setext headings in document order")
    func outlineOrderAndSetext() {
        let source = "# One\n\ntext\n\nTwo\n===\n\n### Three ###\n"
        let output = MarkdownParser.parse(source)
        #expect(output.outline.map(\.level) == [1, 1, 3])
        #expect(output.outline.map(\.title) == ["One", "Two", "Three"])
        #expect(output.outline.map(\.range.location) == [0, 13, 22])
    }

    @Test("Frontmatter is dimmed as one range and keeps later syntax")
    func frontmatterRange() {
        let source = "---\ntitle: Moby\n---\n# Heading\n"
        let output = MarkdownParser.parse(source)
        let frontmatter = output.spans.filter { $0.kind == .frontmatter }
        #expect(frontmatter.count == 1)
        #expect(frontmatter.first?.range == NSRange(location: 0, length: 19))
        #expect(output.spans.contains { $0.kind == .headingMarker })
    }

    @Test("An unclosed frontmatter block is not treated as frontmatter")
    func unclosedFrontmatter() {
        let source = "---\ntitle: Moby\n\n# Heading\n"
        let output = MarkdownParser.parse(source)
        #expect(!output.spans.contains { $0.kind == .frontmatter })
    }

    @Test("Line starts and character count survive unicode")
    func lineStarts() {
        let source = "🌊 a\nb\nc"
        let output = MarkdownParser.parse(source)
        #expect(output.lineStarts == [0, 5, 7])
        #expect(output.lineCount == 3)
        #expect(output.characterCount == 8)
    }

    @Test("Word counts ignore Markdown structure")
    func wordCounts() {
        let source = """
        # Heading

        - one
        - two

        [a link](https://example.com) and https://example.com
        """
        #expect(MarkdownParser.parse(source).wordCount == 7)
    }

    @Test("Frontmatter never appears in the outline")
    func frontmatterIsNotAHeading() {
        let output = MarkdownParser.parse("---\ntitle: A report\ndate: today\n---\n\n# Real\n")
        #expect(output.outline.map(\.title) == ["Real"])
    }

    @Test("The heading-only outline equals the full parse's outline")
    func outlineOnlyMatchesFullParse() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        var sources = [
            "---\ntitle: x\n---\n\n# A\n\nB\n===\n\n> ## Quoted\n\n- ### In a list\n\nC\n---\n",
            "#Not\n\n####### seven\n\n# Trailing #\n",
        ]
        for name in ["example.md", "cheatsheet.md", "lessons/01-basics.md", "lessons/06-frontmatter.md"] {
            sources.append(try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8))
        }
        for source in sources {
            #expect(MarkdownParser.outline(source) == MarkdownParser.parse(source).outline)
        }
    }

    @Test("The parse reports where bold, italic and heading text lie")
    func styleRanges() {
        let source = "## Head line\n\nA **bold** and *it* and ***both***.\n\n`**code**`\n"
        let text = source as NSString
        let output = MarkdownParser.parse(source)
        func covered(_ word: String, _ style: MarkdownTextStyle) -> Bool {
            let range = text.range(of: word)
            return output.styleRanges.contains { $0.style == style && NSLocationInRange(range.location, $0.range) && NSMaxRange(range) <= NSMaxRange($0.range) }
        }
        #expect(covered("Head line", .heading))
        #expect(covered("bold", .strong))
        #expect(covered("it", .emphasis))
        #expect(covered("both", .strong) && covered("both", .emphasis))
        #expect(!output.styleRanges.contains { NSLocationInRange(text.range(of: "code").location, $0.range) }, "code is never styled")
    }
}
