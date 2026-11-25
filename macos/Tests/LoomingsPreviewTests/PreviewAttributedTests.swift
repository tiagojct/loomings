import AppKit
import Testing
@testable import LoomingsPreview

@Suite("Attributed preview")
struct PreviewAttributedTests {
    @Test("Blocks carry source lines and ranges")
    func blocksAndMappings() {
        let source = "# Title\n\nParagraph\n"
        let document = PreviewRenderer().render(source: source, documentURL: nil)

        #expect(document.blocks.count == 2)
        #expect(document.blocks[0].kind == .heading)
        #expect(document.blocks[0].sourceLine == 0)
        #expect(document.blocks[0].sourceRange == NSRange(location: 0, length: 7))
        #expect(document.blocks[1].kind == .paragraph)
        #expect(document.blocks[1].sourceLine == 2)
        #expect(document.attributed.string.contains("Title"))
        #expect(!document.attributed.string.contains("# "))
    }

    @Test("Inline styles, links and linkified URLs")
    func inlineStyles() {
        let source = "A *paragraph* with **strong**, `code` and https://example.com.\n"
        let document = PreviewRenderer().render(source: source, documentURL: nil)
        let text = document.attributed.string

        #expect(text.contains("paragraph"))
        #expect(!text.contains("*paragraph*"))
        #expect(!text.contains("`code`"))
        #expect(document.attributed.ranges(of: .link).count >= 1)

        var italic = false
        var bold = false
        document.attributed.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: document.attributed.length)
        ) { value, _, _ in
            guard let font = value as? NSFont else { return }
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.italicFontMask) { italic = true }
            if traits.contains(.boldFontMask) { bold = true }
        }
        #expect(italic)
        #expect(bold)
    }

    @Test("HTML linkification does not duplicate a URL suffix")
    func urlWithEmailHTML() {
        let document = PreviewRenderer().render(
            source: "https://user@example.com/path and https://two@example.org/other\n",
            documentURL: nil
        )

        #expect(document.html.contains(
            "<a href=\"https://user@example.com/path\" rel=\"noopener noreferrer\">https://user@example.com/path</a>"
        ))
        #expect(document.html.contains(
            "<a href=\"https://two@example.org/other\" rel=\"noopener noreferrer\">https://two@example.org/other</a>"
        ))
        #expect(document.html.components(separatedBy: "<a ").count - 1 == 2)
    }

    @Test("Typographer substitutions match the web")
    func typographer() {
        let source = "Smart \"quotes\" and -- and --- and ... and (c) +-.\n"
        let document = PreviewRenderer().render(source: source, documentURL: nil)
        let text = document.attributed.string
        #expect(text.contains("“quotes”"))
        #expect(text.contains("–"))
        #expect(text.contains("—"))
        #expect(text.contains("…"))
        #expect(text.contains("©"))
        #expect(text.contains("±"))
    }

    @Test("Images become attachments with sanitised sources")
    func images() {
        let source = "![Alt](./pic.png) ![Bad](javascript:alert(1))\n"
        let document = PreviewRenderer().render(source: source, documentURL: nil)
        var sources: [String] = []
        var alts: [String] = []
        document.attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: document.attributed.length)
        ) { value, range, _ in
            guard value is NSTextAttachment else { return }
            if let source = document.attributed.attribute(
                .loomingsImageURL,
                at: range.location,
                effectiveRange: nil
            ) as? String {
                sources.append(source)
            }
            if let alt = document.attributed.attribute(
                .loomingsImageAlt,
                at: range.location,
                effectiveRange: nil
            ) as? String {
                alts.append(alt)
            }
        }
        #expect(sources == ["./pic.png"])
        #expect(alts == ["Alt"])
        #expect(document.attributed.string.contains("![Bad](javascript:alert(1))"))
    }

    @Test("Frontmatter is omitted")
    func frontmatter() {
        let source = "---\ntitle: Hidden\n---\n\n# Visible\n"
        let document = PreviewRenderer().render(source: source, documentURL: nil)
        #expect(!document.attributed.string.contains("Hidden"))
        #expect(document.attributed.string.contains("Visible"))
        #expect(document.blocks.first?.sourceLine == 4)
    }

    @Test("Tables and unicode render without loss")
    func tablesAndUnicode() {
        let source = "| a | b |\n| --- | --- |\n| 1 | 2 |\n\nHéading 🌊 e\u{0301}\n"
        let document = PreviewRenderer().render(source: source, documentURL: nil)
        let text = document.attributed.string
        #expect(text.contains("a"))
        #expect(text.contains("1"))
        #expect(text.contains("Héading 🌊"))
        #expect(document.blocks.count == 2)
    }

    @Test("Nested blocks in quotes and lists render recursively and preserve styles")
    func nestedBlocks() throws {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: "nested-blocks",
            withExtension: "md",
            subdirectory: "Fixtures"
        ))
        let expectedURL = try #require(Bundle.module.url(
            forResource: "nested-blocks",
            withExtension: "html",
            subdirectory: "Fixtures"
        ))
        let source = try String(contentsOf: fixtureURL, encoding: .utf8)
        let expectedHTML = try String(contentsOf: expectedURL, encoding: .utf8)
        let document = PreviewRenderer().render(source: source, documentURL: nil)
        let text = document.attributed.string

        // HTML parity including fenced code language inside quote and tight/loose lists
        #expect(document.html == expectedHTML)
        #expect(document.html.contains("<pre><code data-line=\"2\" class=\"language-swift\">let quoted = 1\n</code></pre>"))

        // Headings, tables, rules, lists, and code inside quotes or list items keep their text
        #expect(text.contains("Quoted Heading"))
        #expect(text.contains("let quoted = 1"))
        #expect(text.contains("quoted item a"))
        #expect(text.contains("quoted item b"))
        #expect(text.contains("col"))
        #expect(text.contains("val"))
        #expect(text.contains("const y = 2;"))
        #expect(text.contains("Nested Heading"))
        #expect(text.contains("nested quote"))
        #expect(text.contains("loose first"))
        #expect(text.contains("second paragraph"))
        #expect(text.contains("z = 3"))

        // Rules inside quote and list item produce attachment placeholders
        var attachmentCount = 0
        document.attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: document.attributed.length)
        ) { value, _, _ in
            if value is NSTextAttachment { attachmentCount += 1 }
        }
        #expect(attachmentCount >= 2)

        // Code block inside quote keeps its own NSTextBlock alongside the quote border block
        let nsText = text as NSString
        let codeRange = nsText.range(of: "let quoted = 1")
        #expect(codeRange.location != NSNotFound)
        if codeRange.location != NSNotFound {
            let style = try #require(document.attributed.attribute(
                .paragraphStyle,
                at: codeRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle)
            #expect(style.textBlocks.count == 2)
            #expect(style.textBlocks.contains { $0.backgroundColor != nil })
        }

        // Table cell inside quote keeps its NSTextTableBlock
        let cellRange = nsText.range(of: "val")
        #expect(cellRange.location != NSNotFound)
        if cellRange.location != NSNotFound {
            let style = try #require(document.attributed.attribute(
                .paragraphStyle,
                at: cellRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle)
            #expect(style.textBlocks.contains { $0 is NSTextTableBlock })
        }

        // List inside quote keeps its tab stops and indent
        let listRange = nsText.range(of: "quoted item a")
        #expect(listRange.location != NSNotFound)
        if listRange.location != NSNotFound {
            let style = try #require(document.attributed.attribute(
                .paragraphStyle,
                at: listRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle)
            #expect(!style.tabStops.isEmpty)
            #expect(style.headIndent > style.firstLineHeadIndent)
        }
    }

    @Test("Loose lists inside blockquotes preserve blank lines between blocks")
    func quotedLooseList() throws {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: "quoted-loose-list",
            withExtension: "md",
            subdirectory: "Fixtures"
        ))
        let expectedURL = try #require(Bundle.module.url(
            forResource: "quoted-loose-list",
            withExtension: "html",
            subdirectory: "Fixtures"
        ))
        let source = try String(contentsOf: fixtureURL, encoding: .utf8)
        let expectedHTML = try String(contentsOf: expectedURL, encoding: .utf8)
        let document = PreviewRenderer().render(source: source, documentURL: nil)

        #expect(document.html == expectedHTML)
        #expect(document.html.contains("<li data-line=\"0\">\n<p data-line=\"0\">first item</p>"))
        #expect(document.html.contains("<p data-line=\"2\">second paragraph in first item</p>"))
        #expect(document.html.contains("<li data-line=\"4\">\n<p data-line=\"4\">second item</p>"))
    }
}

@Suite("Preview URLs and export")
struct PreviewURLTests {
    @Test("Safe and unsafe schemes follow the web")
    func schemes() {
        #expect(PreviewURL.sanitizedLink("https://example.com") != nil)
        #expect(PreviewURL.sanitizedLink("mailto:a@example.com") != nil)
        #expect(PreviewURL.sanitizedLink("#anchor") != nil)
        #expect(PreviewURL.sanitizedLink("./file.png") != nil)
        #expect(PreviewURL.sanitizedLink("/absolute.png") != nil)
        #expect(PreviewURL.sanitizedLink("javascript:alert(1)") == nil)
        #expect(PreviewURL.sanitizedLink("ftp://example.com") == nil)

        #expect(PreviewURL.sanitizedImage("data:image/png;base64,AAAA") != nil)
        #expect(PreviewURL.markdownItRejects("javascript:alert(1)", isImage: false))
        #expect(PreviewURL.markdownItRejects("javascript:alert(1)", isImage: true))
        #expect(!PreviewURL.markdownItRejects("data:image/png;base64,AAAA", isImage: true))
        #expect(PreviewURL.markdownItRejects("data:text/html,x", isImage: false))
    }

    @Test("Standalone HTML escapes the title")
    func exportWrapper() {
        let html = PreviewHTMLExport.document(
            title: "<Title & \"more\">",
            bodyHTML: "<p>Body</p>"
        )
        #expect(html.contains("<title>&lt;Title &amp; &quot;more&quot;&gt;</title>"))
        #expect(html.contains("<p>Body</p>"))
        #expect(html.contains("<!DOCTYPE html>"))
    }
}
