import AppKit
import Foundation
import LoomingsDocuments
import LoomingsEditor
import LoomingsMarkdown
import LoomingsShare

/// Exercises the real window, text view and parse pipeline without a human
/// at the keyboard. Run with `Loomings --self-test`; exit status 0 is proof.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        var failures: [String] = []

        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("ok  \(message)")
            } else {
                failures.append(message)
                print("FAIL \(message)")
            }
        }

        print("Loomings native self-test")
        check(ThemeManager.shared.library != nil, "the ten palettes load from the bundle")
        check(NSFont(name: "JetBrainsMono-Regular", size: 15) != nil, "JetBrains Mono is bundled")
        check(NSFont(name: "SourceSerif4-Regular", size: 15) != nil, "Source Serif 4 is bundled")

        let document = LoomingsDocument()
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()

        guard let controller = document.windowControllers.first as? EditorWindowController else {
            print("FAIL could not create the editor window")
            return 1
        }

        controller.showWindow(nil)
        guard let window = controller.window else {
            print("FAIL editor window has no NSWindow")
            return 1
        }
        window.orderFront(nil)

        let editor = controller.editor
        let textView = editor.textView
        check(editor.palette != nil, "the editor receives a resolved palette")
        check(
            textView.accessibilityLabel() == "Markdown document",
            "the editor has an accessibility label"
        )
        check(
            controller.previewAccessibilityLabel == "Document preview",
            "the preview has an accessibility label"
        )

        if let root = Bundle.main.resourceURL {
            let lessons = (try? FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("lessons"),
                includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "md" }.count ?? 0
            check(lessons == 6, "all six lessons are bundled")
            check(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("example.md").path),
                "the example is bundled"
            )
            check(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("cheatsheet.md").path),
                "the cheatsheet is bundled"
            )
        }

        do {
            let shared = "# Shared\n\nOlá 🌊\n"
            let payload = try ShareLink.encode(shared)
            check(try ShareLink.decode(payload) == shared, "share payloads round-trip")
            let shareURL = try ShareLink.url(for: shared, family: "goney", mode: "dark")
            let parsed = try ShareLink.parse(shareURL)
            check(
                parsed.text == shared && parsed.family == "goney" && parsed.mode == "dark",
                "share URLs carry text and appearance"
            )
        } catch {
            check(false, "share link round trip (\(error))")
        }

        do {
            let shareSource = "# Shared self-test\n\nOlá 🌊\n"
            editor.setText(shareSource)
            let savedClipboard = NSPasteboard.general.string(forType: .string)
            controller.copyShareLink(nil)
            let copied = NSPasteboard.general.string(forType: .string) ?? ""
            check(
                copied.hasPrefix("https://loomings.tiagojacinto.eu/app/"),
                "Copy Share Link writes the website URL"
            )
            let parsed = try ShareLink.parse(string: copied)
            check(parsed.text == shareSource, "the copied share link carries the document")
            NSPasteboard.general.clearContents()
            if let savedClipboard {
                NSPasteboard.general.setString(savedClipboard, forType: .string)
            }
        } catch {
            check(false, "copy share link (\(error))")
        }

        let savedFamily = ThemeManager.shared.family
        let savedMode = ThemeManager.shared.mode
        ThemeManager.shared.family = "rosebud"
        ThemeManager.shared.mode = .light
        controller.applyPreferences()
        check(
            editor.palette?.family == "rosebud" && editor.palette?.mode == .light,
            "theme switching applies to the editor"
        )
        ThemeManager.shared.family = savedFamily
        ThemeManager.shared.mode = savedMode
        ThemeManager.shared.applyAppearance()
        controller.applyPreferences()
        // The self-test drives the run loop directly rather than through
        // NSApplication.run; continuous spell checking on a 240 KB paste then
        // competes with the parse timers. Spelling is exercised in the app,
        // not here.
        textView.isContinuousSpellCheckingEnabled = false

        // 1. Markdown styling lands, and it never becomes document content.
        let markdown = "# The whale\n\nA paragraph with *emphasis*, **strong** and `code`.\n\n- one\n- two\n\n> a quotation\n\n```swift\nlet x = 1\n```\n"
        editor.setText(markdown)
        let styled = pump { editor.lastAppliedRevision == editor.revision && editor.lastSpanCount > 0 }
        check(styled, "parse and styling finish for a small document")
        check(editor.lastSpanCount > 10, "syntax spans cover the document")
        check(editor.lastNodeCount > 10, "syntax tree was walked")

        var effectiveRange = NSRange()
        let storageColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: &effectiveRange
        ) as? NSColor
        let markerColor = EditorController.color(for: .headingMarker)
        check(storageColor != markerColor, "styling uses rendering attributes, not text storage")
        let defaultStorageColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        check(
            defaultStorageColor == nil || defaultStorageColor == editor.palette?.colors.text,
            "document text uses the palette text colour"
        )
        check(textView.textStorage?.string == markdown, "document text is unchanged by styling")

        // 2. Typing, undo and redo through the real text view.
        let end = (markdown as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: end, length: 0))
        check(editor.source == markdown + "x", "typing inserts at the caret")

        textView.undoManager?.undo()
        check(editor.source == markdown, "undo reverts the insertion")
        textView.undoManager?.redo()
        check(editor.source == markdown + "x", "redo restores the insertion")

        let appliedAfterTyping = pump { editor.lastAppliedRevision == editor.revision }
        check(appliedAfterTyping, "styling catches up after typing")

        // 3. A large paste, then immediate typing while the parse is pending.
        let paste = String(repeating: "A pasted line, with a *marker* and `code`.\n", count: 4000)
        let pasteStart = (editor.source as NSString).length
        textView.insertText(paste, replacementRange: NSRange(location: pasteStart, length: 0))
        check(editor.source.count == markdown.count + 1 + paste.count, "large paste is inserted verbatim")

        let caret = (editor.source as NSString).length
        for _ in 0..<5 {
            textView.insertText("z", replacementRange: NSRange(location: caret, length: 0))
            textView.setSelectedRange(NSRange(location: (editor.source as NSString).length, length: 0))
        }
        check(editor.source.hasSuffix("zzzzz"), "typing stays synchronous during a pending parse")
        let converged = pump(timeout: 15) { editor.lastAppliedRevision == editor.revision }
        check(converged, "the last parse wins over stale results")
        check(editor.lastAppliedRevision == editor.revision, "applied parse matches the current revision")
        if !converged {
            print("  revision=\(editor.revision) applied=\(editor.lastAppliedRevision) requests=\(editor.parseRequests) appliedParses=\(editor.appliedParses) discarded=\(editor.discardedParses) parseMs=\(editor.lastParseNanoseconds / 1_000_000)")
        }

        // 4. Unicode before markers must not shift the styled ranges.
        let unicode = "# Héading 🌊\n\n*naïve* — café `crème`\n\n- 🌊 item\n"
        editor.setText(unicode)
        let unicodeParsed = pump { editor.lastAppliedRevision == editor.revision }
        check(unicodeParsed, "unicode document parses")
        check(editor.lastSpanCount > 0, "unicode document produces syntax spans")

        // 5. Marked text (IME) must not crash or corrupt the buffer.
        editor.setText("hello ")
        let helloEnd = (editor.source as NSString).length
        textView.setSelectedRange(NSRange(location: helloEnd, length: 0))
        textView.setMarkedText(
            "に",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: helloEnd, length: 0)
        )
        textView.insertText("にほ", replacementRange: textView.markedRange())
        textView.unmarkText()
        if !editor.source.contains("にほ") {
            print("  composition result: \(editor.source.debugDescription)")
        }
        check(editor.source.contains("にほ"), "marked text commits (にほ)")
        let compositionParsed = pump { editor.lastAppliedRevision == editor.revision }
        check(compositionParsed, "parse runs after composition commits")

        // 6. Programmatic replacement while an old parse is in flight.
        editor.setText("# first\n\none two three\n")
        editor.setText("# second\n\nfour five six\n")
        let replaced = pump(timeout: 15) { editor.lastAppliedRevision == editor.revision }
        check(replaced, "replacement converges on the current revision")
        check(editor.source.contains("second"), "stale parse never overwrites newer text")

        // 7. Spelling attribute passes must not advance the parse revision.
        editor.setText("teh sea and teh whale")
        _ = pump { editor.lastAppliedRevision == editor.revision }
        let revisionBeforeSpelling = editor.revision
        textView.isContinuousSpellCheckingEnabled = true
        textView.checkTextInDocument(nil)
        _ = pump(timeout: 2) { false }
        check(
            editor.revision == revisionBeforeSpelling,
            "spelling attributes do not advance the revision"
        )
        textView.isContinuousSpellCheckingEnabled = false

        // 8. UTF-8 document round trip.
        let saved = "# Save\n\n¡Hola! 🌊\n"
        editor.setText(saved)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-selftest-\(UUID().uuidString).md")
        do {
            let data = try document.data(ofType: "net.daringfireball.markdown")
            try data.write(to: url)
            let read = try String(contentsOf: url, encoding: .utf8)
            check(read == saved, "UTF-8 document data round-trips")
            try? FileManager.default.removeItem(at: url)
        } catch {
            check(false, "UTF-8 document data round-trips (\(error))")
        }

        // 9. Native document features.
        check(LoomingsDocument.autosavesInPlace, "native autosave is enabled")
        check(LoomingsDocument.preservesVersions, "document versions are enabled")

        // 10. BOM and line endings survive a full document round trip.
        let bomCRLF = Data([0xEF, 0xBB, 0xBF])
            + Data("line one\r\nline two\r\n".utf8)
        let encodingDocument = LoomingsDocument()
        NSDocumentController.shared.addDocument(encodingDocument)
        encodingDocument.makeWindowControllers()
        do {
            try encodingDocument.read(
                from: bomCRLF,
                ofType: "net.daringfireball.markdown"
            )
            let roundTripped = try encodingDocument.data(
                ofType: "net.daringfireball.markdown"
            )
            let encodingEditor = (encodingDocument.windowControllers.first as? EditorWindowController)?.editor
            check(roundTripped == bomCRLF, "UTF-8 BOM and CRLF round-trip through NSDocument")
            check(
                encodingEditor?.source == "line one\nline two\n",
                "the editor addresses LF-normalised text"
            )
        } catch {
            check(false, "BOM/CRLF document round trip (\(error))")
        }
        encodingDocument.updateChangeCount(.changeCleared)
        encodingDocument.close()

        // 10b. Save to Shelf never detaches a document from its own file.
        let guardRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-shelf-guard-\(UUID().uuidString)", isDirectory: true)
        let guardFile = guardRoot.appendingPathComponent("own.md")
        try? FileManager.default.createDirectory(at: guardRoot, withIntermediateDirectories: true)
        try? Data("keep\n".utf8).write(to: guardFile)
        let ownFileDocument = LoomingsDocument()
        ownFileDocument.shelf = LocalShelf(root: guardRoot.appendingPathComponent("shelf"))
        ownFileDocument.fileURL = guardFile
        check(!ownFileDocument.canSaveToShelf, "Save to Shelf is unavailable for a document with its own file")
        ownFileDocument.saveToShelf(nil)
        check(ownFileDocument.fileURL == guardFile, "Save to Shelf leaves a document attached to its own file")
        let untitledDocument = LoomingsDocument()
        untitledDocument.shelf = ownFileDocument.shelf
        check(untitledDocument.canSaveToShelf, "Save to Shelf is available for an untitled document")
        try? FileManager.default.removeItem(at: guardRoot)

        // 11. Typing marks the document edited; undoing back to the saved
        // text clears it (NSDocument's undo integration is live).
        let dirtyDocument = LoomingsDocument()
        NSDocumentController.shared.addDocument(dirtyDocument)
        dirtyDocument.makeWindowControllers()
        if let dirtyController = dirtyDocument.windowControllers.first as? EditorWindowController {
            let dirtyEditor = dirtyController.editor
            dirtyEditor.setText("abc")
            dirtyDocument.updateChangeCount(.changeCleared)
            let dirtyText = dirtyEditor.textView
            let dirtyEnd = (dirtyEditor.source as NSString).length
            dirtyText.setSelectedRange(NSRange(location: dirtyEnd, length: 0))
            dirtyText.insertText("x", replacementRange: NSRange(location: dirtyEnd, length: 0))
            _ = pump(timeout: 2) { dirtyDocument.isDocumentEdited }
            check(dirtyDocument.isDocumentEdited, "typing marks the document edited")

            dirtyText.undoManager?.undo()
            _ = pump(timeout: 2) { !dirtyDocument.isDocumentEdited }
            check(!dirtyDocument.isDocumentEdited, "undo back to saved text clears the edited state")
        } else {
            check(false, "could not create the dirty-tracking window")
        }
        dirtyDocument.updateChangeCount(.changeCleared)
        dirtyDocument.close()

        // 12. Autosave writes an edited file-backed document in place.
        let autosaveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-autosave-\(UUID().uuidString).md")
        do {
            try Data("original\n".utf8).write(to: autosaveURL)
            let autosaveDocument = LoomingsDocument()
            autosaveDocument.fileURL = autosaveURL
            autosaveDocument.fileType = "net.daringfireball.markdown"
            NSDocumentController.shared.addDocument(autosaveDocument)
            autosaveDocument.makeWindowControllers()
            try autosaveDocument.read(
                from: Data("original\n".utf8),
                ofType: "net.daringfireball.markdown"
            )
            autosaveDocument.updateChangeCount(.changeCleared)

            if let autosaveController = autosaveDocument.windowControllers.first as? EditorWindowController {
                let autosaveText = autosaveController.editor.textView
                let autosaveEnd = (autosaveController.editor.source as NSString).length
                autosaveText.setSelectedRange(NSRange(location: autosaveEnd, length: 0))
                autosaveText.insertText("x", replacementRange: NSRange(location: autosaveEnd, length: 0))
                _ = pump(timeout: 2) { autosaveDocument.isDocumentEdited }

                var autosaveError: Error?
                autosaveDocument.autosave(withImplicitCancellability: false) { error in
                    autosaveError = error
                }
                let wrote = pump(timeout: 5) {
                    (try? String(contentsOf: autosaveURL, encoding: .utf8)) == "original\nx"
                }
                check(autosaveError == nil, "autosave reports no error")
                check(wrote, "autosave writes the edited file in place")
            } else {
                check(false, "could not create the autosave window")
            }

            autosaveDocument.updateChangeCount(.changeCleared)
            autosaveDocument.close()
            try? FileManager.default.removeItem(at: autosaveURL)
        } catch {
            check(false, "autosave setup (\(error))")
        }

        // 13. Saving to a local shelf creates a stable, readable entry.
        let shelfRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-selftest-shelf-\(UUID().uuidString)", isDirectory: true)
        let testShelf = LocalShelf(root: shelfRoot)
        let shelfDocument = LoomingsDocument()
        shelfDocument.shelf = testShelf
        shelfDocument.notesRecentDocuments = false
        NSDocumentController.shared.addDocument(shelfDocument)
        shelfDocument.makeWindowControllers()
        if let shelfController = shelfDocument.windowControllers.first as? EditorWindowController {
            shelfController.editor.setText("# Shelf\n\nbody\n")
            shelfDocument.saveToShelf(nil)

            let entries = (try? testShelf.entries()) ?? []
            let content = shelfDocument.fileURL.flatMap {
                try? String(contentsOf: $0, encoding: .utf8)
            }
            check(entries.count == 1, "save to shelf creates one entry")
            check(shelfDocument.displayName == "Shelf", "shelf save derives a title")
            check(content == "# Shelf\n\nbody\n", "shelf content matches the editor")
            check(!shelfDocument.isContentEdited, "shelf save clears the content generation")
            if let id = shelfDocument.shelfEntry?.id {
                try? testShelf.delete(id: id)
            }
        } else {
            check(false, "could not create the shelf window")
        }
        shelfDocument.updateChangeCount(.changeCleared)
        shelfDocument.close()
        try? FileManager.default.removeItem(at: shelfRoot)

        // 13b. Preview modes render the document.
        editor.setText("# Preview\n\nBody with *emphasis*.\n")
        controller.setViewMode(.split)
        _ = pump(timeout: 2) { controller.previewText.contains("Body with") }
        check(controller.isPreviewVisible, "split mode shows the preview")
        check(controller.previewText.contains("Body with"), "split mode renders the document")
        check(!controller.previewText.contains("*emphasis*"), "preview strips Markdown markers")
        controller.setViewMode(.write)

        // 13c. Preview rendering, modes and export.
        editor.setText("# Preview table\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\nEmoji 🌊\n")
        controller.setViewMode(.split)
        _ = pump(timeout: 2) { controller.previewText.contains("Emoji") }
        check(controller.previewText.contains("1"), "preview renders table cells")
        check(controller.previewText.contains("🌊"), "preview keeps emoji")

        let exportedHTML = controller.renderedHTMLForTesting()
        check(exportedHTML.contains("<h1 data-line=\"0\">Preview table</h1>"), "HTML export contains the heading")
        check(exportedHTML.contains("<table data-line=\"2\">"), "HTML export contains the table")
        check(exportedHTML.contains("🌊"), "HTML export keeps emoji")
        if let background = ThemeManager.shared.resolved()?.colors.bg {
            check(exportedHTML.contains(background), "HTML export uses the selected palette")
        }

        let pdf = controller.renderedPDFForTesting()
        check(pdf.starts(with: Data("%PDF".utf8)), "PDF export produces a PDF")
        check(pdf.count > 1_000, "PDF export has content")

        controller.setViewMode(.preview)
        _ = pump(timeout: 1) { controller.isPreviewVisible && !controller.isEditorVisible }
        check(controller.isPreviewVisible, "preview mode shows the preview")
        check(!controller.isEditorVisible, "preview mode hides the editor")

        controller.setViewMode(.split)
        editor.setText("# Preview table\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\nEmoji 🌊\n\nSecond paragraph.\n")
        _ = pump(timeout: 2) { controller.previewText.contains("Second paragraph") }
        check(controller.previewText.contains("Second paragraph"), "preview updates incrementally")

        // A render identical to the previous one used to index past the last
        // block range; appending at the end uses the same prefix boundary.
        editor.setText("# Stable\n\nSame body.\n")
        _ = pump(timeout: 2) { controller.previewText.contains("Same body") }
        editor.setText("# Stable\n\nSame body.\n")
        _ = pump(timeout: 1) { false }
        check(controller.previewText.contains("Same body"), "identical preview renders are safe")
        editor.setText("# Stable\n\nSame body.\n\nAppended at the end.\n")
        _ = pump(timeout: 2) { controller.previewText.contains("Appended at the end") }
        check(
            controller.previewText.contains("Appended at the end"),
            "appending to the preview is safe"
        )

        editor.setText("# Stress\n\n")
        let stressView = editor.textView
        for index in 0..<24 {
            let end = (editor.source as NSString).length
            stressView.insertText(
                "word \(index) ",
                replacementRange: NSRange(location: end, length: 0)
            )
        }
        _ = pump(timeout: 3) { controller.previewText.contains("word 23") }
        check(
            controller.previewText.contains("word 23"),
            "typing in split view updates the preview safely"
        )
        editor.setText("")
        _ = pump(timeout: 2) { controller.previewText.isEmpty }
        check(controller.previewText.isEmpty, "clearing the document clears the preview")
        controller.setViewMode(.write)

        let longText = (0..<120).map { "Line \($0)\n\n" }.joined()
        editor.setText(longText)
        editor.reparseSynchronously()
        controller.setViewMode(.split)
        _ = pump(timeout: 1) { controller.previewText.contains("Line 119") }
        editor.scrollToLine(80)
        _ = pump(timeout: 1) {
            abs((controller.previewTopLine ?? 0) - Double(controller.editorTopLine - 1)) < 12
        }
        check(
            abs((controller.previewTopLine ?? 0) - Double(controller.editorTopLine - 1)) < 12,
            "editor scrolling drives the preview (editor \(controller.editorTopLine), preview \(controller.previewTopLine ?? -1))"
        )
        Thread.sleep(forTimeInterval: 0.2)
        controller.scrollPreviewForTesting(toSourceLine: 100)
        _ = pump(timeout: 1) { controller.editorTopLine > 80 }
        check(controller.editorTopLine > 80, "preview scrolling drives the editor")
        controller.setViewMode(.write)

        // 13d. Frontmatter is dimmed in the editor.
        editor.setText("---\ntitle: Hidden\n---\n# Visible\n")
        editor.reparseSynchronously()
        _ = pump(timeout: 1) { false }
        let frontmatterColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        let expectedFrontmatter = editor.palette?.colors.textGhost ?? .tertiaryLabelColor
        check(frontmatterColor == expectedFrontmatter, "frontmatter is dimmed in the editor (got \(String(describing: frontmatterColor)))")

        // 14. Editing and reading parity.
        check(textView.usesFindBar, "native find bar is available")

        editor.setText("# One\n\nTwo\n===\n")
        editor.reparseSynchronously()
        check(editor.outline.map(\.level) == [1, 1], "outline includes setext headings")
        check(editor.outline.map(\.title) == ["One", "Two"], "outline titles are clean")
        check(editor.analysis.wordCount == 2, "word count feeds the status bar")

        editor.setText("word")
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        _ = editor.toggleBold()
        check(editor.source == "**word**", "bold wraps the selection")
        editor.textView.undoManager?.undo()
        check(editor.source == "word", "formatting is undoable")

        editor.setText("hello ")
        textView.insertText(
            "\"",
            replacementRange: NSRange(location: 6, length: 0)
        )
        check(editor.source == "hello “", "smart quotes are applied while typing")

        editor.setText("# One\n\nSecond sentence. Third sentence.\n")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        document.updateChangeCount(.changeCleared)
        editor.setFocusMode(true)
        check(editor.isFocusMode, "focus mode can be enabled")
        _ = pump(timeout: 1) { false }
        let dimColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 20,
            effectiveRange: nil
        ) as? NSColor
        let activeColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 2,
            effectiveRange: nil
        ) as? NSColor
        let expectedDim = editor.palette?.colors.textGhost ?? .tertiaryLabelColor
        let expectedActive = editor.palette?.colors.text ?? .labelColor
        check(dimColor == expectedDim, "focus mode dims text outside the active sentence")
        check(activeColor == expectedActive, "focus mode keeps the active sentence at full contrast")
        check(!document.isDocumentEdited, "focus mode does not dirty the document")
        editor.setFocusMode(false)
        let clearedColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: 20,
            effectiveRange: nil
        ) as? NSColor
        let baseColor = editor.palette?.colors.text ?? .labelColor
        check(
            clearedColor == nil || clearedColor == baseColor,
            "focus mode restores the base colour when disabled"
        )
        check(!editor.isFocusMode, "focus mode can be disabled")

        editor.setFontSize(19)
        check(textView.font?.pointSize == 19, "font size applies to the editor")
        editor.setFontSize(15)

        if let scrollView = textView.enclosingScrollView {
            scrollView.rulersVisible = true
            check(scrollView.rulersVisible, "the line-number ruler can be shown")
            scrollView.rulersVisible = EditorPreferences.showLineNumbers
        }

        editor.setText(String(repeating: "line\n", count: 2_000))
        editor.reparseSynchronously()
        let typeEnd = (editor.source as NSString).length
        textView.setSelectedRange(NSRange(location: max(0, typeEnd - 2), length: 0))
        _ = pump(timeout: 1) { false }
        editor.setTypewriterMode(true)
        let centered = pump(timeout: 3) {
            (textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0) > 0
        }
        check(centered, "typewriter mode scrolls the caret into view")
        editor.setTypewriterMode(false)

        // 15. A save that started before newer edits cannot clear them.
        var generation = SaveGeneration()
        generation.recordSave(snapshot: 4)
        check(generation.isEdited(currentGeneration: 5), "older save leaves newer edits edited")
        generation.recordSave(snapshot: 4)
        check(generation.isEdited(currentGeneration: 5), "a late older save still cannot clear them")
        generation.recordSave(snapshot: 5)
        check(!generation.isEdited(currentGeneration: 5), "the save at the latest generation clears them")

        document.updateChangeCount(.changeCleared)
        window.orderOut(nil)
        document.close()

        if failures.isEmpty {
            print("SELFTEST PASS")
            return 0
        }
        print("SELFTEST FAIL (\(failures.count))")
        for failure in failures {
            print("  - \(failure)")
        }
        return 1
    }

    private static func pump(timeout: TimeInterval = 5, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return condition()
    }
}
