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
}
