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
