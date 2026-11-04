import AppKit
import Testing
@testable import LoomingsEditor

@MainActor
@Suite("Editor controller")
struct EditorControllerTests {
    @Test("Pasting a URL over selected words makes a link")
    func pasteLink() {
        let editor = EditorController()
        editor.setText("Call me Ishmael.\n")
        editor.textView.setSelectedRange(NSRange(location: 8, length: 7))
        #expect(editor.pasteLink("https://example.org"))
        #expect(editor.source == "Call me [Ishmael](https://example.org).\n")
        #expect(editor.textView.selectedRange() == NSRange(location: 38, length: 0))
    }

    @Test("Pasting with no selection, or over a placeholder, stays a plain paste")
    func plainPaste() {
        let editor = EditorController()
        editor.setText("[word](url)\n")
        #expect(!editor.pasteLink("https://example.org"))
        editor.textView.setSelectedRange(NSRange(location: 7, length: 3))
        #expect(!editor.pasteLink("https://example.org"))
        #expect(editor.source == "[word](url)\n")
    }

    @Test("A dropped image goes in at the point, with its alt text selected")
    func oneImage() {
        let editor = EditorController()
        editor.setText("ab\n")
        editor.insertImages(
            [URL(fileURLWithPath: "/Users/a/lung-chart.png")],
            at: 1,
            relativeTo: URL(fileURLWithPath: "/Users/a")
        )
        #expect(editor.source == "a![lung chart](./lung-chart.png)b\n")
        #expect(editor.textView.selectedRange() == NSRange(location: 3, length: 10))
    }

    @Test("Dropped images each take a paragraph")
    func twoImages() {
        let editor = EditorController()
        editor.setText("")
        editor.insertImages(
            [URL(fileURLWithPath: "/a/one.png"), URL(fileURLWithPath: "/a/two.png")],
            at: 99,
            relativeTo: nil
        )
        #expect(editor.source == "![one](/a/one.png)\n\n![two](/a/two.png)")
    }

    @Test("Smart typography rests while text is marked")
    func markedText() {
        let editor = EditorController()
        editor.setText("")
        let textView = editor.textView
        textView.setMarkedText("'", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.hasMarkedText())
        #expect(editor.textView(textView, shouldChangeTextIn: NSRange(location: 1, length: 0), replacementString: "'"))
        #expect(!editor.source.contains("‘"))
    }

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

@MainActor
@Suite("Citation completion")
struct CitationCompletionTests {
    nonisolated private static let keys = [
        CitationCompletion(key: "silva2020", authors: "Silva", year: "2020", title: "Lung function at home"),
        CitationCompletion(key: "jacome2021", authors: "Jácome, Costa", year: "2021", title: "Saúde e pulmão"),
    ]

    private static let bibliography = "---\nbibliography: refs.bib\n---\n"

    private func editor(_ text: String, keys: [CitationCompletion] = keys) -> EditorController {
        let editor = EditorController()
        editor.setText(text)
        editor.reparseSynchronously()
        editor.setCitations([], keys: keys, reportedSource: text)
        editor.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return editor
    }

    private func offers(_ editor: EditorController) -> [String] {
        var index = -1
        let range = editor.textView.rangeForUserCompletion
        return editor.textView.completions(forPartialWordRange: range, indexOfSelectedItem: &index) ?? []
    }

    private func type(_ text: String, in editor: EditorController) {
        editor.textView.asTyping {
            editor.textView.insertText(text, replacementRange: editor.textView.selectedRange())
        }
    }

    private func offersKey(_ editor: EditorController, _ key: String) -> Bool {
        offers(editor).contains { $0.hasPrefix(key + " ") }
    }

    @Test("The sign after a space offers each key, with its authors and year")
    func afterSpace() {
        let editor = editor("A claim @")
        #expect(editor.textView.rangeForUserCompletion == NSRange(location: 8, length: 1))
        #expect(offers(editor) == ["silva2020  Silva 2020", "jacome2021  Jácome, Costa 2021"])
    }

    @Test("The sign after a bracket, a hyphen or a line start offers keys")
    func otherStarts() {
        #expect(offersKey(editor("A claim [@"), "silva2020"))
        #expect(offersKey(editor("A claim [-@"), "silva2020"))
        #expect(offersKey(editor("@"), "silva2020"))
    }

    @Test("Nothing in an email address or after a backslash")
    func email() {
        #expect(!offersKey(editor("ana@sil"), "silva2020"))
        #expect(!offersKey(editor("\\@sil"), "silva2020"))
        #expect(!offersKey(editor("ção@sil"), "silva2020"))
    }

    @Test("The first item is selected, so Return takes it")
    func firstSelected() {
        let editor = editor("A claim @")
        var index = -1
        _ = editor.textView.completions(forPartialWordRange: editor.textView.rangeForUserCompletion, indexOfSelectedItem: &index)
        #expect(index == 0)
    }

    @Test("Each word of the query must be in the key, the authors or the title")
    func matching() {
        #expect(offers(editor("@silv")) == ["silva2020  Silva 2020"])
        #expect(offers(editor("@lung home")) == ["silva2020  Silva 2020"])
        #expect(offers(editor("@costa")) == ["jacome2021  Jácome, Costa 2021"])
        #expect(offers(editor("@nobody")).isEmpty)
    }

    @Test("Accents and case are ignored in both directions")
    func folding() {
        #expect(offersKey(editor("@jacome"), "jacome2021"))
        #expect(offersKey(editor("@JÁCOME"), "jacome2021"))
        #expect(offersKey(editor("@saude"), "jacome2021"))
        #expect(offersKey(editor("@pulmão"), "jacome2021"))
    }

    @Test("The query stops at brackets, semicolons, line ends and a far sign")
    func queryLimits() {
        #expect(!offersKey(editor("[@a] sil"), "silva2020"))
        #expect(!offersKey(editor("[@a; sil"), "silva2020"))
        #expect(!offersKey(editor("@\nsil"), "silva2020"))
        #expect(!offersKey(editor("@" + String(repeating: "s", count: 41)), "silva2020"))
    }

    @Test("A second citation in a group has its own query")
    func group() {
        #expect(offers(editor("[@a; @silv")) == ["silva2020  Silva 2020"])
    }

    @Test("No list with an empty library")
    func emptyLibrary() {
        let editor = editor("A claim @", keys: [])
        #expect(editor.textView.rangeForUserCompletion != NSRange(location: 8, length: 1))
        #expect(!offersKey(editor, "silva2020"))
    }

    @Test("No list in the frontmatter")
    func frontmatter() {
        let text = "---\nauthor: @x\n---\nBody.\n"
        let editor = editor(text)
        editor.textView.setSelectedRange(NSRange(location: 13, length: 0))
        #expect(!offersKey(editor, "silva2020"))
    }

    @Test("No list in inline code, in a fence or in an indented block")
    func code() {
        let inline = "A `code @ here` line.\n"
        let first = editor(inline)
        first.textView.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(!offersKey(first, "silva2020"))

        let after = "A `code` and @ here.\n"
        let second = editor(after)
        second.textView.setSelectedRange(NSRange(location: 14, length: 0))
        #expect(offersKey(second, "silva2020"))

        let fence = "```\n@ here\n```\n"
        let third = editor(fence)
        third.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(!offersKey(third, "silva2020"))

        let block = "Text.\n\n    @ here\n"
        let fourth = editor(block)
        fourth.textView.setSelectedRange(NSRange(location: 12, length: 0))
        #expect(!offersKey(fourth, "silva2020"))
    }

    @Test("A manual list waits for the parse: code ranges do not move with an edit")
    func staleCodeRangeBelow() {
        let text = "```\n@ here\n```\n"
        let editor = editor(text)
        let above = String(repeating: "word ", count: 20) + "\n\n"
        editor.replace(range: NSRange(location: 0, length: 0), with: above)
        let sign = (above as NSString).length + 4
        editor.textView.setSelectedRange(NSRange(location: sign + 1, length: 0))
        #expect(!offersKey(editor, "silva2020"))
        editor.reparseSynchronously()
        #expect(!offersKey(editor, "silva2020"))
    }

    @Test("Text that moves out of an old code range gets its list after the parse")
    func staleCodeRangeAbove() {
        let block = "```\ncode line\n```\n\n"
        let editor = editor(block + "@")
        editor.replace(range: NSRange(location: 0, length: (block as NSString).length), with: "")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(!offersKey(editor, "silva2020"))
        editor.reparseSynchronously()
        #expect(offersKey(editor, "silva2020"))
    }

    @Test("No list while text is marked")
    func markedText() {
        let editor = editor("A claim @")
        let textView = editor.textView
        textView.setMarkedText("s", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 9, length: 0))
        #expect(textView.hasMarkedText())
        #expect(!offersKey(editor, "silva2020"))
    }

    @Test("Return and Tab insert the key with its sign")
    func accepted() {
        for movement in [NSTextMovement.return, .tab] {
            let editor = editor("A claim [@si")
            let range = editor.textView.rangeForUserCompletion
            let first = offers(editor)[0]
            editor.textView.insertCompletion(first, forPartialWordRange: range, movement: movement.rawValue, isFinal: true)
            #expect(editor.source == "A claim [@silva2020")
        }
    }

    @Test("Browsing, Escape and a typed letter leave the text as it is")
    func notAccepted() {
        let editor = editor("A claim @")
        let range = editor.textView.rangeForUserCompletion
        let first = offers(editor)[0]
        editor.textView.insertCompletion(first, forPartialWordRange: range, movement: NSTextMovement.down.rawValue, isFinal: false)
        #expect(editor.source == "A claim @")
        editor.textView.insertCompletion(first, forPartialWordRange: range, movement: 0, isFinal: true)
        #expect(editor.source == "A claim @")
        _ = offers(editor)
        editor.textView.insertCompletion("@", forPartialWordRange: range, movement: NSTextMovement.cancel.rawValue, isFinal: true)
        #expect(editor.source == "A claim @")
    }

    @Test("Text with no list keeps the system's insertion")
    func systemWords() {
        let editor = editor("A wo")
        let range = editor.textView.rangeForUserCompletion
        _ = offers(editor)
        editor.textView.insertCompletion("word", forPartialWordRange: range, movement: NSTextMovement.return.rawValue, isFinal: true)
        #expect(editor.source == "A word")
    }

    @Test("A typed sign arms the list for the next parse")
    func armed() {
        let editor = editor(Self.bibliography + "A claim ")
        type("@", in: editor)
        #expect(editor.isCompletionArmed)
    }

    @Test("A sign from code does not arm the list")
    func programmaticSign() {
        let replaced = editor("A claim ")
        replaced.replace(range: NSRange(location: 8, length: 0), with: "@")
        #expect(!replaced.isCompletionArmed)

        let inserted = editor("A claim ")
        inserted.textView.insertText("@", replacementRange: inserted.textView.selectedRange())
        #expect(!inserted.isCompletionArmed)
    }

    @Test("A pasted sign, an email and a marked sign do not arm the list")
    func notArmed() {
        let pasted = editor("A claim ")
        type("@silva", in: pasted)
        #expect(!pasted.isCompletionArmed)

        let email = editor("ana")
        type("@", in: email)
        #expect(!email.isCompletionArmed)

        let marked = editor("A claim ")
        marked.textView.setMarkedText("@", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 8, length: 0))
        #expect(!marked.isCompletionArmed)
    }

    @Test("A document with no library never arms the list")
    func noLibraryNoArm() {
        let editor = editor("A claim ", keys: [])
        type("@", in: editor)
        #expect(!editor.isCompletionArmed)
    }

    @Test("A letter after the sign arms the list again, but a space does not")
    func narrowing() {
        let editor = editor("A claim @")
        type("s", in: editor)
        #expect(editor.isCompletionArmed)

        let spaced = self.editor("A claim @")
        type(" ", in: spaced)
        #expect(!spaced.isCompletionArmed)
    }

    @Test("Escape holds the list back until the next sign")
    func dismissed() {
        let editor = editor("A claim @")
        let range = editor.textView.rangeForUserCompletion
        _ = offers(editor)
        editor.textView.insertCompletion("@", forPartialWordRange: range, movement: NSTextMovement.cancel.rawValue, isFinal: true)
        type("s", in: editor)
        #expect(!editor.isCompletionArmed)
        type(" ", in: editor)
        type("[", in: editor)
        type("@", in: editor)
        #expect(editor.isCompletionArmed)
    }

    @Test("Smart typography still works beside the list")
    func smartTypography() {
        let editor = editor("A claim @si ")
        let textView = editor.textView
        textView.insertText("\"", replacementRange: textView.selectedRange())
        #expect(editor.source == "A claim @si \u{201C}")
    }

    @Test("List continuation still works after a key")
    func listContinuation() {
        let editor = editor("- see [@si")
        let range = editor.textView.rangeForUserCompletion
        let first = offers(editor)[0]
        editor.textView.insertCompletion(first, forPartialWordRange: range, movement: NSTextMovement.return.rawValue, isFinal: true)
        #expect(editor.handleNewline())
        #expect(editor.source == "- see [@silva2020\n- ")
    }
}

@Suite("Text change")
struct TextChangeTests {
    private let change = TextChange(range: NSRange(location: 10, length: 2), newLength: 5)

    @Test("A range before the change stays")
    func before() {
        #expect(change.map(NSRange(location: 2, length: 8)) == NSRange(location: 2, length: 8))
    }

    @Test("A range after the change moves by the difference")
    func after() {
        #expect(change.map(NSRange(location: 12, length: 4)) == NSRange(location: 15, length: 4))
    }

    @Test("A range that the change touches is dropped")
    func touched() {
        #expect(change.map(NSRange(location: 9, length: 2)) == nil)
        #expect(change.map(NSRange(location: 11, length: 3)) == nil)
        #expect(change.map(NSRange(location: 8, length: 8)) == nil)
    }

    @Test("An insertion at either end of a range leaves it whole")
    func insertionAtTheEnds() {
        let insertion = TextChange(range: NSRange(location: 5, length: 0), newLength: 1)
        #expect(insertion.map(NSRange(location: 5, length: 3)) == NSRange(location: 6, length: 3))
        #expect(insertion.map(NSRange(location: 2, length: 3)) == NSRange(location: 2, length: 3))
    }

    @Test("An insertion in a range drops it")
    func insertionInside() {
        let insertion = TextChange(range: NSRange(location: 5, length: 0), newLength: 1)
        #expect(insertion.map(NSRange(location: 4, length: 3)) == nil)
    }

    @Test("Two texts give the one change between them")
    func between() throws {
        let change = try #require(TextChange.between("abcdef", "abXYef"))
        #expect(change == TextChange(range: NSRange(location: 2, length: 2), newLength: 2))
        #expect(change.replacement(in: "abXYef") == "XY")
        #expect(TextChange.between("same", "same") == nil)
    }

    @Test("Texts that are equal only after normalisation are different texts")
    func normalisation() throws {
        let change = try #require(TextChange.between("caf\u{E9}", "cafe\u{301}"))
        #expect(change == TextChange(range: NSRange(location: 3, length: 1), newLength: 2))
    }

    @Test("A repeated letter does not count twice")
    func overlap() throws {
        let change = try #require(TextChange.between("aa", "aaa"))
        #expect(change == TextChange(range: NSRange(location: 2, length: 0), newLength: 1))
    }

    @Test("The change does not cut a pair of surrogates")
    func surrogates() throws {
        let change = try #require(TextChange.between("x\u{1F600}y", "x\u{1F601}y"))
        #expect(change == TextChange(range: NSRange(location: 1, length: 2), newLength: 2))
        #expect(change.replacement(in: "x\u{1F601}y") == "\u{1F601}")
    }
}

@MainActor
@Suite("Citation marks")
struct CitationMarkTests {
    nonisolated private static let text = "Claim [@known] and [@gone] end.\n"
    private static let known = NSRange(location: 6, length: 8)
    private static let gone = NSRange(location: 19, length: 7)

    private func editor(_ text: String = text) -> EditorController {
        let editor = EditorController()
        editor.setText(text)
        editor.reparseSynchronously()
        return editor
    }

    private let marks = [
        CitationMark(range: known, isUnknown: false),
        CitationMark(range: gone, isUnknown: true),
    ]

    private func squiggles(_ editor: EditorController) -> [NSRange] {
        editor.textView.decorations(for: "citations").map(\.range)
    }

    @Test("An unknown key gets a squiggle in the notes colour")
    func unknownKey() throws {
        let editor = editor()
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        #expect(editor.citationRanges == [Self.known, Self.gone])
        let decoration = try #require(editor.textView.decorations(for: "citations").first)
        #expect(squiggles(editor) == [Self.gone])
        guard case .squiggle = decoration.style else {
            Issue.record("not a squiggle")
            return
        }
    }

    @Test("The text storage of a new text view has no delegate to chain to")
    func storageDelegate() {
        #expect(EditorTextView(usingTextLayoutManager: true).textStorage?.delegate == nil)
        let editor = editor()
        #expect(editor.textView.textStorage?.delegate === editor)
    }

    @Test("Marks never advance the revision")
    func revision() {
        let editor = editor()
        let revision = editor.revision
        let generation = editor.editGeneration
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        editor.clearCitations()
        #expect(editor.revision == revision)
        #expect(editor.editGeneration == generation)
    }

    @Test("Marks do not change the text storage")
    func storage() throws {
        let editor = editor()
        let storage = try #require(editor.textView.textStorage)
        let before = try #require(storage.copy() as? NSAttributedString)
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        #expect(storage.isEqual(to: before))
    }

    @Test("A report for an older text moves its marks to the new text")
    func lateReport() {
        let editor = editor("New. " + Self.text)
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        #expect(squiggles(editor) == [NSRange(location: 24, length: 7)])
        #expect(editor.citationRanges.first == NSRange(location: 11, length: 8))
    }

    @Test("A report for an older text drops the marks that the edit touched")
    func lateReportTouched() {
        let changed = Self.text.replacingOccurrences(of: "[@gone]", with: "[@goner]")
        let editor = editor(changed)
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        #expect(squiggles(editor).isEmpty)
        #expect(editor.citationRanges == [Self.known])
    }

    @Test("Marks follow an edit before them, and stay for an edit after them")
    func follow() {
        let editor = editor()
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        editor.replace(range: NSRange(location: 0, length: 0), with: "Yes. ")
        #expect(squiggles(editor) == [NSRange(location: 24, length: 7)])
        editor.replace(range: NSRange(location: 35, length: 0), with: " Tail")
        #expect(squiggles(editor) == [NSRange(location: 24, length: 7)])
    }

    @Test("An edit in a mark drops it, and the others stay")
    func dropTouched() {
        let editor = editor()
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        editor.replace(range: NSRange(location: 22, length: 1), with: "x")
        #expect(squiggles(editor).isEmpty)
        #expect(editor.citationRanges == [Self.known])
    }

    @Test("A new report puts a dropped mark back")
    func newReport() {
        let editor = editor()
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        editor.replace(range: NSRange(location: 22, length: 1), with: "x")
        let source = editor.source
        editor.setCitations(marks, keys: [], reportedSource: source)
        #expect(squiggles(editor) == [Self.gone])
    }

    @Test("Attribute changes do not move the marks")
    func attributes() throws {
        let editor = editor()
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        let storage = try #require(editor.textView.textStorage)
        storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 5))
        #expect(squiggles(editor) == [Self.gone])
    }

    @Test("A new text drops the marks, and the same text keeps them")
    func setText() {
        let editor = editor()
        editor.setCitations(marks, keys: [], reportedSource: Self.text)
        editor.setText(Self.text)
        #expect(squiggles(editor) == [Self.gone])
        editor.setText("Other.\n")
        #expect(editor.citationRanges.isEmpty)
        #expect(squiggles(editor).isEmpty)
    }

    @Test("Clear removes the marks and the keys")
    func clear() {
        let editor = editor()
        let key = CitationCompletion(key: "a", authors: "", year: "", title: "")
        editor.setCitations(marks, keys: [key], reportedSource: Self.text)
        editor.clearCitations()
        #expect(editor.citationRanges.isEmpty)
        #expect(editor.citationKeys.isEmpty)
        #expect(squiggles(editor).isEmpty)
    }
}
