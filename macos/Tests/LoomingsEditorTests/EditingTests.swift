import AppKit
import Testing
@testable import LoomingsEditor

@Suite("Markdown editing rules")
struct MarkdownEditingTests {
    @Test("List and quotation continuation")
    func continuation() {
        #expect(MarkdownEditing.continuation(forLine: "- item")
            == .init(replacementLine: nil, insertion: "\n- "))
        #expect(MarkdownEditing.continuation(forLine: "  * item")
            == .init(replacementLine: nil, insertion: "\n  * "))
        #expect(MarkdownEditing.continuation(forLine: "1. item")
            == .init(replacementLine: nil, insertion: "\n2. "))
        #expect(MarkdownEditing.continuation(forLine: "9) item")
            == .init(replacementLine: nil, insertion: "\n10) "))
        #expect(MarkdownEditing.continuation(forLine: "> quote")
            == .init(replacementLine: nil, insertion: "\n> "))
        #expect(MarkdownEditing.continuation(forLine: "- ")
            == .init(replacementLine: "", insertion: nil))
        #expect(MarkdownEditing.continuation(forLine: "> ")
            == .init(replacementLine: "", insertion: nil))
        #expect(MarkdownEditing.continuation(forLine: "plain text") == nil)
    }

    @Test("Indent and outdent every non-empty line")
    func indentation() {
        #expect(MarkdownEditing.indent("a\n\nb") == "  a\n\n  b")
        #expect(MarkdownEditing.outdent("  a\n\n  b") == "a\n\nb")
        #expect(MarkdownEditing.outdent(" a") == "a")
    }

    @Test("Smart typography")
    func smartTypography() {
        func replacement(_ input: Character, at location: Int, in text: String) -> SmartTypography.Replacement? {
            SmartTypography.replacement(
                for: input,
                at: location,
                in: text as NSString
            )
        }

        #expect(replacement("\"", at: 0, in: "")?.text == "“")
        #expect(replacement("\"", at: 6, in: "hello ")?.text == "“")
        #expect(replacement("\"", at: 5, in: "hellox")?.text == "”")
        #expect(replacement("'", at: 0, in: "")?.text == "‘")
        #expect(replacement("'", at: 4, in: "don'")?.text == "’")
        #expect(replacement("-", at: 1, in: "a") == nil)
        #expect(replacement("-", at: 2, in: "a-")?.text == "—")
        #expect(replacement("-", at: 2, in: "a-")?.range == NSRange(location: 1, length: 1))
        #expect(replacement(".", at: 3, in: "a..")?.text == "…")
        #expect(replacement(".", at: 3, in: "a..")?.range == NSRange(location: 1, length: 2))
    }
}

@Suite("Sentence focus")
struct SentenceFocusTests {
    @Test("The sentence under the caret is active")
    func activeSentence() {
        let text = "One. Two! Three?" as NSString
        #expect(SentenceFocus.activeRange(in: text, caret: 6) == NSRange(location: 4, length: 5))
        #expect(SentenceFocus.activeRange(in: text, caret: 0) == NSRange(location: 0, length: 4))
    }

    @Test("A trailing blank line ends the paragraph")
    func paragraphEndBeforeBlankLine() {
        let text = "First.\n\nSecond." as NSString
        #expect(SentenceFocus.activeRange(in: text, caret: 0) == NSRange(location: 0, length: 6))
    }

    @Test("Blank lines bound the paragraph")
    func paragraphBounds() {
        let text = "First paragraph.\n\nSecond one. Still second." as NSString
        let range = SentenceFocus.activeRange(in: text, caret: 25)
        #expect(range == NSRange(location: 18, length: 11))
    }

    @Test("An empty document has an empty active range")
    func emptyDocument() {
        #expect(SentenceFocus.activeRange(in: "" as NSString, caret: 0).length == 0)
    }
}

@MainActor
@Suite("Editor commands")
struct EditorCommandTests {
    @Test("Bold wraps and unwraps the selection")
    func boldToggle() {
        let editor = EditorController()
        editor.setText("word")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        _ = editor.toggleBold()
        #expect(editor.source == "**word**")

        editor.textView.setSelectedRange(NSRange(location: 0, length: 8))
        _ = editor.toggleBold()
        #expect(editor.source == "word")
    }

    @Test("Italic layers on bold without destroying it")
    func italicLayering() {
        let editor = EditorController()
        editor.setText("**bold**")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 8))
        _ = editor.toggleItalic()
        #expect(editor.source == "***bold***")

        editor.textView.setSelectedRange(NSRange(location: 0, length: 10))
        _ = editor.toggleItalic()
        #expect(editor.source == "**bold**")
    }

    @Test("An empty bold command leaves the caret inside the markers")
    func boldCaret() {
        let editor = EditorController()
        editor.setText("")
        _ = editor.toggleBold()
        #expect(editor.source == "****")
        #expect(editor.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test("Inline code and links follow the web editor")
    func codeAndLink() {
        let editor = EditorController()
        editor.setText("text")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        _ = editor.toggleInlineCode()
        #expect(editor.source == "`text`")

        editor.textView.setSelectedRange(NSRange(location: 0, length: 6))
        _ = editor.insertLink()
        #expect(editor.source == "[`text`](url)")
        #expect(editor.textView.selectedRange() == NSRange(location: 9, length: 3))

        editor.setText("")
        _ = editor.insertLink()
        #expect(editor.source == "[](url)")
        #expect(editor.textView.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test("Enter continues a list and an empty item ends it")
    func newlineContinuation() {
        let editor = EditorController()
        editor.setText("- item")
        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(editor.handleNewline())
        #expect(editor.source == "- item\n- ")

        editor.textView.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(editor.handleNewline())
        #expect(editor.source == "- item\n")
    }

    @Test("Tab indents the selected lines")
    func tabIndent() {
        let editor = EditorController()
        editor.setText("a\nb")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(editor.handleIndent(outdent: false))
        #expect(editor.source == "  a\n  b")

        editor.textView.setSelectedRange(NSRange(location: 0, length: 7))
        #expect(editor.handleIndent(outdent: true))
        #expect(editor.source == "a\nb")
    }

    @Test("Typing applies smart typography")
    func smartTyping() {
        let editor = EditorController()
        editor.setText("hello ")
        let end = (editor.source as NSString).length
        editor.textView.insertText("\"", replacementRange: NSRange(location: end, length: 0))
        #expect(editor.source == "hello “")

        editor.setText("a-")
        editor.textView.insertText("-", replacementRange: NSRange(location: 2, length: 0))
        #expect(editor.source == "a—")

        editor.setText("a..")
        editor.textView.insertText(".", replacementRange: NSRange(location: 3, length: 0))
        #expect(editor.source == "a…")
    }

    @Test("Statistics follow the document and the selection")
    func statistics() {
        let editor = EditorController()
        editor.setText("One two three.")
        editor.reparseSynchronously()
        #expect(editor.analysis.wordCount == 3)
        #expect(editor.analysis.lineCount == 1)

        editor.textView.setSelectedRange(NSRange(location: 0, length: 7))
        #expect(editor.selectionStatistics()
            == SelectionStatistics(words: 2, characters: 7, lines: 1))
    }
}
