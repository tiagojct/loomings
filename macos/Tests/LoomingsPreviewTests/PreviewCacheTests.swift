import AppKit
import Foundation
import Testing
@testable import LoomingsPreview

/// The renderer reuses blocks between renders. Whatever it reuses must be
/// indistinguishable from rendering from scratch: same attributed text, same
/// source ranges and lines, same HTML (including its `data-line` numbers).
@Suite("Preview block cache")
struct PreviewCacheTests {
    private static let sample = """
    # Title

    A paragraph with [a link][ref], *emphasis* and `code`.

    - one
      - nested
    - two

    > quoted text

    ```swift
    let x = 1
    ```

    | a | b |
    |---|---|
    | 1 | 2 |

    ---

    ![alt](pic.png)

    Last paragraph.

    [ref]: https://one.example

    """

    private func lessons() throws -> String {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        var text = ""
        for name in ["lessons/01-basics.md", "lessons/02-lists-quotes.md", "lessons/05-tables-rules.md"] {
            text += try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8) + "\n\n"
        }
        return text
    }

    /// What a reader sees, run by run. NSAttributedString.isEqual is not usable
    /// here: text blocks, text tables and attachments compare by identity, so
    /// two fresh renders of the same quote or table are never "equal".
    private func appearance(_ text: NSAttributedString) -> [String] {
        var runs: [String] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var parts = [(text.string as NSString).substring(with: range)]
            for key in attributes.keys.map(\.rawValue).sorted() {
                let value = attributes[NSAttributedString.Key(key)]
                switch value {
                case let font as NSFont:
                    parts.append("\(key)=\(font.fontName) \(font.pointSize)")
                case let color as NSColor:
                    parts.append("\(key)=\(color.usingColorSpace(.sRGB)?.description ?? color.description)")
                case let style as NSParagraphStyle:
                    parts.append("\(key)=\(style.alignment.rawValue) \(style.headIndent) \(style.firstLineHeadIndent) \(style.paragraphSpacing) \(style.paragraphSpacingBefore) \(style.lineHeightMultiple) blocks=\(style.textBlocks.count) lists=\(style.textLists.count)")
                case let attachment as NSTextAttachment:
                    parts.append("\(key)=\(attachment.bounds)")
                default:
                    parts.append("\(key)=\(String(describing: value))")
                }
            }
            runs.append(parts.joined(separator: "|"))
        }
        return runs
    }

    private func expectSame(_ cached: PreviewDocument, _ fresh: PreviewDocument, _ label: String) {
        #expect(cached.html == fresh.html, "\(label): html")
        #expect(cached.blocks.count == fresh.blocks.count, "\(label): block count")
        for (index, pair) in zip(cached.blocks, fresh.blocks).enumerated() {
            let (left, right) = pair
            #expect(left.kind == right.kind, "\(label): kind \(index)")
            #expect(left.sourceRange == right.sourceRange, "\(label): range \(index)")
            #expect(left.sourceLine == right.sourceLine, "\(label): line \(index)")
            #expect(left.html == right.html, "\(label): block html \(index)")
            #expect(appearance(left.attributed) == appearance(right.attributed), "\(label): text \(index)")
        }
    }

    @Test("A cached render equals a fresh one after every kind of edit")
    func equivalentAfterEdits() throws {
        let base = Self.sample + (try lessons())
        let nsBase = base as NSString
        let edits: [(String, (String) -> String)] = [
            ("insert above", { "New first paragraph.\n\n" + $0 }),
            ("insert a surrogate pair above", { "é😀 café\n\n" + $0 }),
            ("edit in the middle", { text in
                let middle = (text as NSString).range(of: "Last paragraph.")
                return (text as NSString).replacingCharacters(in: middle, with: "Last paragraph, edited.")
            }),
            ("remove the heading", { $0.replacingOccurrences(of: "# Title\n\n", with: "") }),
            ("change a reference definition", { $0.replacingOccurrences(of: "one.example", with: "two.example") }),
            ("add a blank line in a list", { $0.replacingOccurrences(of: "- one\n", with: "- one\n\n") }),
            ("append", { $0 + "\nAppended.\n" }),
            ("empty", { _ in "" }),
        ]

        let cached = PreviewRenderer()
        expectSame(
            cached.render(source: base, documentURL: nil),
            PreviewRenderer().render(source: base, documentURL: nil),
            "first render"
        )
        #expect(nsBase.length > 0)

        for (name, edit) in edits {
            let edited = edit(base)
            expectSame(
                cached.render(source: edited, documentURL: nil),
                PreviewRenderer().render(source: edited, documentURL: nil),
                name
            )
            // Go back to the base so each edit is measured against it.
            expectSame(
                cached.render(source: base, documentURL: nil),
                PreviewRenderer().render(source: base, documentURL: nil),
                "\(name), restored"
            )
        }
    }

    @Test("Editing one block renders only that block again")
    func reusesUnchangedBlocks() throws {
        let renderer = PreviewRenderer()
        let first = renderer.render(source: Self.sample, documentURL: nil)
        #expect(renderer.reusedBlockCount == 0)

        let edited = Self.sample.replacingOccurrences(of: "Last paragraph.", with: "Last paragraph, edited.")
        let second = renderer.render(source: edited, documentURL: nil)
        #expect(second.blocks.count == first.blocks.count)
        #expect(renderer.reusedBlockCount == first.blocks.count - 1)

        // Unchanged text is the same object, so the view can skip comparing it.
        #expect(second.blocks[0].attributed === first.blocks[0].attributed)
    }

    @Test("A reference definition elsewhere invalidates the links that use it")
    func referenceDefinitions() throws {
        let renderer = PreviewRenderer()
        _ = renderer.render(source: Self.sample, documentURL: nil)
        let changed = Self.sample.replacingOccurrences(of: "one.example", with: "two.example")
        let rendered = renderer.render(source: changed, documentURL: nil)
        #expect(rendered.html.contains("two.example"))
        #expect(!rendered.html.contains("one.example"))
    }

    @Test("A new theme or document clears the cache")
    func themeAndDocumentInvalidate() throws {
        let renderer = PreviewRenderer()
        _ = renderer.render(source: Self.sample, documentURL: nil)

        var themed = PreviewTheme.standard
        themed.textColor = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        renderer.theme = themed
        let recoloured = renderer.render(source: Self.sample, documentURL: nil)
        #expect(renderer.reusedBlockCount == 0)
        expectSame(recoloured, PreviewRenderer(theme: themed).render(source: Self.sample, documentURL: nil), "new theme")

        _ = renderer.render(source: Self.sample, documentURL: URL(fileURLWithPath: "/tmp/a.md"))
        #expect(renderer.reusedBlockCount == 0)
        _ = renderer.render(source: Self.sample, documentURL: URL(fileURLWithPath: "/tmp/a.md"))
        #expect(renderer.reusedBlockCount > 0)
        _ = renderer.render(source: Self.sample, documentURL: URL(fileURLWithPath: "/tmp/b.md"))
        #expect(renderer.reusedBlockCount == 0)
    }
}
