import AppKit
import Testing
@testable import LoomingsEditor

@MainActor
@Suite("Editor controller")
struct EditorControllerTests {
    @Test("Parse applies to the current revision")
    func parseAppliesToTheCurrentRevision() {
        let editor = EditorController()
        editor.setText("# Title\n\nSome *emphasis* and `code`.\n")
        editor.reparseSynchronously()

        #expect(editor.lastAppliedRevision == editor.revision)
        #expect(editor.lastSpanCount > 0)
        #expect(editor.lastNodeCount > 0)
    }

    @Test("Styling never writes to text storage")
    func stylingNeverWritesToTextStorage() {
        let editor = EditorController()
        let source = "# Heading\n\n*emphasis* and **strong**\n"
        editor.setText(source)
        editor.reparseSynchronously()

        var effective = NSRange()
        let color = editor.textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: &effective
        ) as? NSColor
        #expect(color != EditorController.color(for: .headingMarker))
        #expect(editor.textView.string == source)
    }

    @Test("Latest text wins when parsing repeatedly")
    func latestTextWins() {
        let editor = EditorController()
        editor.setText("# first\n\none two three\n")
        editor.setText("# second\n\nfour five six\n")
        editor.reparseSynchronously()

        #expect(editor.source.contains("second"))
        #expect(editor.lastAppliedRevision == editor.revision)
    }

    @Test("Handler stays fast while a parse is pending")
    func handlerStaysFastWhileAParseIsPending() {
        let editor = EditorController()
        let textView = editor.textView
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))

        #expect(editor.lastAppliedRevision == 0, "the parse cannot have completed synchronously")
        #expect(editor.lastEditHandlerNanoseconds < 8_000_000)
        #expect(editor.parseRequests == 0, "no snapshot happens on the edit path")
        #expect(editor.source == "x")
    }

    @Test("Companion analysis runs with each parse and arrives with the analysis")
    func companionArrivesWithAnalysis() {
        let editor = EditorController()
        editor.companionAnalysis = { source in source.count }
        editor.setText("abc")
        editor.reparseSynchronously()
        #expect(editor.companionResult as? Int == 3)

        editor.setText("abcdef")
        editor.reparseSynchronously()
        #expect(editor.companionResult as? Int == 6)
    }

    @Test("Companion analysis runs off the main thread on the debounced parse")
    func companionRunsOffMain() async throws {
        let editor = EditorController()
        editor.companionAnalysis = { _ in Thread.isMainThread }
        editor.setText("hello")
        #expect(editor.companionResult == nil, "a new text starts without a companion result")
        for _ in 0..<100 where editor.companionResult == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(editor.companionResult as? Bool == false)
    }

    @Test("A new text drops the previous companion result")
    func newTextDropsCompanionResult() {
        let editor = EditorController()
        editor.companionAnalysis = { source in source.count }
        editor.setText("abc")
        editor.reparseSynchronously()
        editor.setText("xy")
        #expect(editor.companionResult == nil)
    }

    @Test("Companion analysis runs alongside the parse, not after it")
    func companionRunsInParallel() async throws {
        let editor = EditorController()
        editor.companionAnalysis = { _ in
            let started = DispatchTime.now().uptimeNanoseconds
            Thread.sleep(forTimeInterval: 0.3)
            return started
        }
        editor.setText(String(repeating: "# Heading\n\nA paragraph with *emphasis*.\n\n", count: 4_000))
        for _ in 0..<500 where editor.companionResult == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let companionStarted = try #require(editor.companionResult as? UInt64)
        // Run after the parse, it would start only once the parse finished.
        #expect(companionStarted < editor.lastParseFinishedAt)
    }

    @Test("Typing a marker at a line start names it")
    func typedMarkersAreNamed() {
        let editor = EditorController()
        var used: [String] = []
        editor.onMarkupUsed = { used.append($0) }
        editor.setText("")
        for text in ["## ", "Title\n", "- ", "item\n", "> ", "q\n", "3. ", "x\n", "```"] {
            editor.textView.insertText(text, replacementRange: editor.textView.selectedRange())
        }
        #expect(used == ["Heading 2: ## ", "Bullet list: - ", "Quote: > ", "Numbered list: 3. ", "Code block: ```"])
    }

    @Test("A marker typed mid-line is not named")
    func midLineMarkersAreQuiet() {
        let editor = EditorController()
        var used: [String] = []
        editor.onMarkupUsed = { used.append($0) }
        editor.setText("")
        editor.textView.insertText("a - b ## c > ", replacementRange: editor.textView.selectedRange())
        #expect(used.isEmpty)
    }

    @Test("Formatting commands name what they did")
    func commandsAreNamed() {
        let editor = EditorController()
        var used: [String] = []
        editor.onMarkupUsed = { used.append($0) }
        editor.setText("word")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        editor.toggleBold()
        #expect(used == ["Bold: **text**"])
    }

    @Test("The current line can be marked")
    func currentLineMark() {
        let editor = EditorController()
        editor.setText("one\ntwo\n")
        editor.highlightsCurrentLine = true
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(editor.textView.decorations(for: "line").map(\.range) == [NSRange(location: 4, length: 4)])
        editor.highlightsCurrentLine = false
        #expect(editor.textView.decorations(for: "line").isEmpty)
    }

    @Test("A slow companion never builds a backlog behind typing")
    func slowCompanionKeepsUp() async throws {
        let editor = EditorController()
        editor.companionAnalysis = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return true
        }
        editor.setText("start\n")
        // A keystroke every 150 ms for 3 s: each pause enqueues a parse.
        for _ in 0..<20 {
            editor.textView.setSelectedRange(NSRange(location: (editor.source as NSString).length, length: 0))
            editor.textView.insertText("x", replacementRange: editor.textView.selectedRange())
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        let stopped = Date()
        for _ in 0..<400 where editor.lastAppliedRevision != editor.revision {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let catchUp = Date().timeIntervalSince(stopped)
        #expect(editor.lastAppliedRevision == editor.revision)
        // One in-flight run plus the last one, not twenty queued runs.
        #expect(catchUp < 1.0, "caught up \(catchUp) s after typing stopped")
    }

    @Test("Drawing looks only at decorations on screen")
    func decorationsAreLimitedToTheVisibleText() throws {
        let editor = EditorController()
        let view = editor.textView
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = view
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        editor.setText((0..<20_000).map { "line \($0)" }.joined(separator: "\n"))
        let text = view.string as NSString
        var marks: [EditorDecoration] = []
        var location = 0
        for index in 0..<20_000 {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            if index % 4 == 0 { marks.append(EditorDecoration(range: line, style: .lineFill(.red))) }
            location = NSMaxRange(line)
        }
        view.setDecorations(marks, for: "test")
        let start = Date()
        let visible = view.decorations(intersecting: NSRect(x: 0, y: 0, width: 600, height: 400))
        let elapsed = Date().timeIntervalSince(start)
        #expect(!visible.isEmpty)
        #expect(visible.count < 60, "\(visible.count) of \(marks.count) treated as visible")
        #expect(elapsed < 0.1, "took \(elapsed) s")
        window.close()
    }

    private func font(_ editor: EditorController, at word: String) -> NSFont? {
        let location = (editor.source as NSString).range(of: word).location
        return editor.textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    private func attribute(_ key: NSAttributedString.Key, _ editor: EditorController, at word: String) -> Any? {
        let location = (editor.source as NSString).range(of: word).location
        return editor.textView.textStorage?.attribute(key, at: location, effectiveRange: nil)
    }

    @Test("Font choices round-trip and set the editor's face")
    func fontChoices() {
        for choice in EditorFontChoice.builtIn {
            #expect(EditorFontChoice(rawValue: choice.rawValue) == choice)
            #expect(!choice.title.isEmpty)
        }
        #expect(EditorFontChoice(rawValue: "custom:Menlo-Regular") == .custom("Menlo-Regular"))
        #expect(EditorFontChoice(rawValue: "nonsense") == nil)
        let editor = EditorController()
        editor.setText("abc def")
        editor.setFontChoice(.custom("Menlo-Regular"))
        #expect(font(editor, at: "def")?.fontName == "Menlo-Regular")
        #expect(editor.fontChoice == .custom("Menlo-Regular"))
    }

    @Test("Styled Markdown sets bold, italic and heading lines, and the text stays unedited")
    func styledMarkdown() {
        let editor = EditorController()
        editor.setFontChoice(.custom("Menlo-Regular"))
        editor.setText("## Head\n\nA **bold** and *it* word.\n")
        editor.stylesMarkdown = true
        editor.reparseSynchronously()
        let manager = NSFontManager.shared
        #expect(font(editor, at: "Head").map { manager.traits(of: $0).contains(.boldFontMask) } == true)
        #expect(font(editor, at: "bold").map { manager.traits(of: $0).contains(.boldFontMask) } == true)
        #expect(font(editor, at: "it*").map { manager.traits(of: $0).contains(.italicFontMask) } == true)
        #expect(font(editor, at: "word")?.fontName == "Menlo-Regular")
        #expect(editor.editGeneration == 0, "styling is not an edit")
        editor.stylesMarkdown = false
        #expect(font(editor, at: "bold")?.fontName == "Menlo-Regular")
    }

    @Test("A face without bold or italic gets drawn ones")
    func syntheticStyles() {
        let editor = EditorController()
        editor.setFontChoice(.custom("Monaco"))
        editor.setText("A **bold** and *it* word.\n")
        editor.stylesMarkdown = true
        editor.reparseSynchronously()
        #expect((attribute(.strokeWidth, editor, at: "bold") as? Double).map { $0 < 0 } == true)
        // TextKit 2 ignores .obliqueness, so the slant must be in the font itself.
        #expect(font(editor, at: "it*").map { $0.textTransform.m21 > 0 } == true)
        #expect(attribute(.strokeWidth, editor, at: "word") == nil)
        #expect(font(editor, at: "word").map { $0.textTransform.m21 == 0 } == true)
        editor.stylesMarkdown = false
        #expect(attribute(.strokeWidth, editor, at: "bold") == nil)
        #expect(font(editor, at: "it*").map { $0.textTransform.m21 == 0 } == true)
    }

    @Test("Bold is never lost when a face has no bold italic")
    func boldItalicKeepsBold() {
        for name in ["Menlo-Regular", "Monaco", "Courier"] {
            guard let base = NSFont(name: name, size: 15) else { continue }
            let face = StyledFace.make(base: base, bold: true, italic: true)
            let bold = NSFontManager.shared.traits(of: face.font).contains(.boldFontMask) || face.attributes[.strokeWidth] != nil
            let slanted = NSFontManager.shared.traits(of: face.font).contains(.italicFontMask) || face.font.textTransform.m21 > 0
            #expect(bold, "\(name) keeps bold")
            #expect(slanted, "\(name) is slanted")
        }
    }
}
