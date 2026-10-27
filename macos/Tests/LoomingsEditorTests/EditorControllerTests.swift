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
}
