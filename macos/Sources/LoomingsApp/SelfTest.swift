import AppKit
import CoreImage
import Foundation
import LoomingsCitations
import LoomingsDocuments
import LoomingsEditor
import LoomingsMarkdown
import LoomingsShare
import LoomingsTeaching
import PDFKit

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

        // 12b. A clean file-backed document follows a change made on disk.
        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-external-\(UUID().uuidString).md")
        do {
            try Data("before\n".utf8).write(to: externalURL)
            let externalDocument = LoomingsDocument()
            externalDocument.fileURL = externalURL
            externalDocument.fileType = "net.daringfireball.markdown"
            NSDocumentController.shared.addDocument(externalDocument)
            externalDocument.makeWindowControllers()
            try externalDocument.read(
                from: Data("before\n".utf8),
                ofType: "net.daringfireball.markdown"
            )
            externalDocument.updateChangeCount(.changeCleared)

            try Data("after, and longer\n".utf8).write(to: externalURL)
            externalDocument.checkForExternalChange()
            let followed = pump(timeout: 3) {
                (externalDocument.windowControllers.first as? EditorWindowController)?
                    .editor.source == "after, and longer\n"
            }
            check(followed, "a clean document reloads an external change")
            check(!externalDocument.isDocumentEdited, "a reloaded document is not marked edited")

            externalDocument.updateChangeCount(.changeCleared)
            externalDocument.close()
            try? FileManager.default.removeItem(at: externalURL)
        } catch {
            check(false, "external change setup (\(error))")
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

        // 13a-1. The learner's checker finds a mistake, fixes it, and undo
        // brings the mistake back.
        editor.setText("Intro.\n\n#Title\n")
        _ = pump(timeout: 2) { !controller.notesForTesting.isEmpty }
        check(controller.notesForTesting == ["heading-space"], "the checker notes a heading without a space")
        check(controller.statusNotesTitleForTesting == "1 note", "the status bar shows the note count")
        controller.applyNoteFixForTesting(0)
        check(editor.source == "Intro.\n\n# Title\n", "a note's fix repairs the text")
        editor.textView.undoManager?.undo()
        check(editor.source == "Intro.\n\n#Title\n", "undo brings the mistake back")
        _ = pump(timeout: 2) { controller.notesForTesting == ["heading-space"] }
        check(editor.textView.decorations(for: "notes").count == 1, "the note is marked in the text")
        editor.setText("#One\n\n#Two\n")
        _ = pump(timeout: 2) { controller.notesForTesting.count == 2 }
        controller.showNotesForTesting()
        check(controller.isNotesPopoverShownForTesting, "the notes list opens")
        controller.fixFromNotesPopoverForTesting(0)
        check(!controller.isNotesPopoverShownForTesting, "a fix closes the notes list, so no stale fix button stays")
        editor.setText("# Clean\n\nNothing to say.\n")
        _ = pump(timeout: 2) { controller.notesForTesting.isEmpty && controller.statusNotesTitleForTesting == nil }
        check(controller.statusNotesTitleForTesting == nil, "a clean document shows no notes")

        // 13a-2. Option-click explains a marker.
        editor.setText("## A\n\n- item\n")
        _ = pump(timeout: 2) { editor.span(at: 0) != nil }
        check(editor.span(at: 0)?.kind == .headingMarker, "the marker under a click is found")
        check(controller.explanationTitleForTesting(at: 1) == "Level-2 heading", "option-click explains a heading marker")
        check(controller.explanationTitleForTesting(at: 6) == "Bullet list item", "option-click explains a list marker")
        check(controller.explanationTitleForTesting(at: 9) == nil, "plain text has no explanation")

        // 13a-3. A bundled lesson's exercises check themselves.
        let lessonFile = "02-lists-quotes.md"
        if let lessonURL = Bundle.main.resourceURL?.appendingPathComponent("lessons/\(lessonFile)"),
           let lessonText = try? String(contentsOf: lessonURL, encoding: .utf8) {
            let lessonChecks = LessonChecks.checks(for: lessonFile)
            check(lessonChecks.count == 3, "the lesson's checks load from the bundle")
            let lessonDocument = LoomingsDocument()
            lessonDocument.pendingText = lessonText
            lessonDocument.attachedChecks = AttachedChecks(checks: lessonChecks, after: lessonText)
            NSDocumentController.shared.addDocument(lessonDocument)
            lessonDocument.makeWindowControllers()
            if let lessonController = lessonDocument.windowControllers.first as? EditorWindowController {
                lessonController.showWindow(nil)
                _ = pump(timeout: 2) { lessonController.exerciseTitleForTesting != nil }
                check(lessonController.exerciseTitleForTesting == "Exercise 0 of 3", "an untouched lesson has no exercise done")
                lessonController.editor.setText(lessonText + "\n- Milk\n- Bread\n- Eggs\n- Rice\n- Tea\n")
                _ = pump(timeout: 2) { lessonController.exerciseTitleForTesting == "Exercise 1 of 3" }
                check(lessonController.exerciseTitleForTesting == "Exercise 1 of 3", "a five-item list passes the first check")
                lessonController.editor.setText(lessonText + "\n- Milk\n- Bread\n- Eggs\n- Rice\n- Tea\n\n1. Boil.\n2. Pour.\n3. Wait.\n\n> A line.\n")
                _ = pump(timeout: 2) { lessonController.exerciseTitleForTesting == "Exercise done" }
                check(lessonController.exerciseTitleForTesting == "Exercise done", "all checks passing says so")
            }
            lessonDocument.updateChangeCount(.changeCleared)
            lessonDocument.close()
        } else {
            check(false, "lesson 02 is bundled")
        }

        // 13a-4. Section word limits.
        editor.setText("---\nlimit: Introduction 5\n---\n\n## Introduction\n\none two three four five six\n\n## Next\n\nseven\n")
        _ = pump(timeout: 2) { controller.outlineTitlesForTesting.count == 2 }
        editor.textView.setSelectedRange(NSRange(location: (editor.source as NSString).range(of: "three").location, length: 0))
        _ = pump(timeout: 1) { controller.sectionTitleForTesting != nil }
        check(controller.sectionTitleForTesting == "Introduction 6 of 5 words", "the status bar counts the caret's section against its limit")
        check(controller.outlineTitlesForTesting == ["Introduction \u{2014} 6/5", "Next \u{2014} 1"], "the outline lists each section's words")
        editor.textView.insertText(" more", replacementRange: editor.textView.selectedRange())
        controller.updateStatusNowForTesting()
        check(controller.sectionTitleForTesting != nil, "the section count stays visible while typing")
        editor.textView.setSelectedRange(NSRange(location: (editor.source as NSString).range(of: "seven").location, length: 0))
        _ = pump(timeout: 2) { controller.sectionTitleForTesting == nil }
        check(controller.sectionTitleForTesting == nil, "a section without a limit shows nothing")

        // 13a-5. Projector mode changes the view, never the preferences.
        func loomingsDefaults() -> NSDictionary {
            UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("Loomings.") } as NSDictionary
        }
        let defaultsBefore = loomingsDefaults()
        let fontBefore = editor.fontSize
        controller.toggleProjectorMode(nil)
        check(controller.isProjectorMode, "projector mode turns on")
        check(editor.fontSize == 28, "projector mode enlarges the editor type")
        check(controller.isStatusBarHiddenForTesting, "projector mode hides the status bar")
        check(!controller.areLineNumbersVisibleForTesting, "projector mode hides line numbers")
        check(editor.highlightsCurrentLine, "projector mode marks the current line")
        editor.setText("")
        editor.textView.insertText("## ", replacementRange: editor.textView.selectedRange())
        check(controller.overlayTextForTesting == "Heading 2: ## ", "the overlay names the markup just typed")
        editor.setText("Body text for the room.\n")
        controller.setViewMode(.split)
        _ = pump(timeout: 2) { controller.previewBodyFontSizeForTesting == 26 }
        check(controller.previewBodyFontSizeForTesting == 26, "projector mode enlarges the preview type")
        controller.setViewMode(.write)
        controller.toggleProjectorMode(nil)
        controller.setViewMode(.split)
        _ = pump(timeout: 2) { controller.previewBodyFontSizeForTesting == 17 }
        check(controller.previewBodyFontSizeForTesting == 17, "turning it off restores the preview type")
        controller.setViewMode(.write)
        controller.toggleProjectorMode(nil)
        controller.toggleProjectorMode(nil)
        check(!controller.isProjectorMode, "projector mode turns off")
        check(editor.fontSize == fontBefore, "turning it off restores the type size")
        check(controller.isStatusBarHiddenForTesting == !EditorPreferences.showStats, "turning it off restores the status bar")
        check(controller.areLineNumbersVisibleForTesting == EditorPreferences.showLineNumbers, "turning it off restores line numbers")
        check(!editor.highlightsCurrentLine, "turning it off clears the line mark")

        // 13a-6. The editor column follows its pane: Split lays it out for
        // half the window, Write for the whole of it again, and dragging the
        // divider lays it out for the new width.
        controller.setViewMode(.write)
        controller.layoutNowForTesting()
        let writeColumn = controller.editorColumnForTesting
        controller.setViewMode(.split)
        _ = pump(timeout: 2) { controller.editorColumnForTesting != writeColumn }
        let splitColumn = controller.editorColumnForTesting
        check(splitColumn != writeColumn, "split view lays the editor column out for its pane")
        controller.moveDividerForTesting(toFraction: 0.35)
        _ = pump(timeout: 2) { controller.editorColumnForTesting != splitColumn }
        check(controller.editorColumnForTesting != splitColumn, "dragging the divider lays the column out again")
        controller.setViewMode(.write)
        _ = pump(timeout: 2) { controller.editorColumnForTesting == writeColumn }
        check(controller.editorColumnForTesting == writeColumn, "leaving split view gives the column the whole window again")
        check(loomingsDefaults() == defaultsBefore, "projector mode writes no preference")

        // 13a-6. The handout is paginated, numbered and carries the link.
        if let handoutURL = Bundle.main.resourceURL?.appendingPathComponent("lessons/05-tables-rules.md"),
           let handoutText = try? String(contentsOf: handoutURL, encoding: .utf8) {
            editor.setText(handoutText + handoutText)
            let handout = controller.renderedPDFForTesting()
            let pdf = PDFDocument(data: handout)
            check((pdf?.pageCount ?? 0) > 1, "the handout runs over several pages")
            check(pdf?.page(at: 0)?.string?.contains("page 1 of") == true, "handout pages are numbered")
            let lastPage = pdf.flatMap { $0.page(at: $0.pageCount - 1)?.string } ?? ""
            check(lastPage.contains("Scan to open this document in Loomings"), "the handout ends with the share link's QR code")
            if let document = pdf, let page = document.page(at: document.pageCount - 1) {
                let bounds = page.bounds(for: .mediaBox)
                let image = page.thumbnail(of: NSSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
                let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
                let decoded = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    .flatMap { detector?.features(in: CIImage(cgImage: $0)) }?
                    .compactMap { ($0 as? CIQRCodeFeature)?.messageString } ?? []
                let expected = try? ShareLink.url(for: editor.source, family: ThemeManager.shared.family, mode: ThemeManager.shared.mode.rawValue)
                check(decoded.first == expected?.absoluteString, "the printed QR code reads back as the share link")
            }
            if let page = pdf?.page(at: 0) {
                let size = page.bounds(for: .mediaBox).size
                let a4 = abs(size.width - 595.28) < 1 && abs(size.height - 841.89) < 1
                let letter = abs(size.width - 612) < 1 && abs(size.height - 792) < 1
                check(a4 || letter, "the handout is A4 or Letter")
            }
        }

        // 13a-7. The share tool offers its actions as a menu.
        check(controller.shareMenuTitlesForTesting == ["Copy Share Link", "Show QR Code\u{2026}", "Send with AirDrop\u{2026}"], "the share tool lists its actions")
        editor.setText("# Sent\n\nUnsaved words.\n")
        if let sendable = controller.airDropFileForTesting() {
            check(sendable.pathExtension == "md", "AirDrop sends a Markdown file")
            check((try? String(contentsOf: sendable, encoding: .utf8)) == "# Sent\n\nUnsaved words.\n", "AirDrop sends the current text, saved or not")
        } else {
            check(false, "AirDrop prepares a file")
        }
        check(controller.airDropAvailableForTesting == (NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: [URL(fileURLWithPath: "/tmp/x.md")]) ?? false), "the AirDrop item follows the system's answer")
        editor.setText("# Short\n")
        check(controller.qrCaptionForTesting == "Scan to open this document in Loomings.", "a short document gets a QR code")
        editor.setText((0..<200).map { _ in "A line that does not compress to nothing: \(UUID().uuidString)\n" }.joined())
        check(controller.qrCaptionForTesting?.contains("too long") == true, "a long document is told it is too long for a QR code")

        // 13a-8. Writing history: opt-in, throttled, survives a save, deletable.
        do {
            let historyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("loomings-selftest-history-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: historyRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: historyRoot) }
            let file = historyRoot.appendingPathComponent("essay.md")
            try "one".write(to: file, atomically: true, encoding: .utf8)
            var now: TimeInterval = 0
            let store = HistoryStore(root: historyRoot.appendingPathComponent("History"))
            let recorder = HistoryRecorder(store: store, clock: { now })
            recorder.load(fileURL: file)
            check(!recorder.isRecording, "a document is not recorded until asked")
            check(store.existingIdentifier(for: file) == nil, "an unrecorded file is never marked")
            recorder.setRecording(true, fileURL: file, text: "one")
            now = 0.5; recorder.textChanged("one two")
            now = 3; recorder.textChanged("one two three")
            now = 3.5; recorder.textChanged("four")
            recorder.flush()
            let id = try store.identifier(for: file)
            let entries = try store.entries(for: id)
            check(entries.count == 3, "edits are recorded at most every two seconds, and the last is flushed")
            check(HistoryLog.reconstruct(entries, upTo: entries.count - 1) == "four", "the history rebuilds the last text")

            let historyDocument = try LoomingsDocument(contentsOf: file, ofType: "net.daringfireball.markdown")
            NSDocumentController.shared.addDocument(historyDocument)
            historyDocument.makeWindowControllers()
            var saved = false
            historyDocument.save(to: file, ofType: historyDocument.fileType ?? "net.daringfireball.markdown", for: .saveOperation) { _ in saved = true }
            _ = pump(timeout: 2) { saved }
            check(store.existingIdentifier(for: file) == id, "the history survives a save")

            let replay = ReplayWindowController(entries: entries, title: "essay", palette: ThemeManager.shared.resolved())
            check(replay.stepCount == 3 && replay.shownText == "four", "the replay opens at the last step")
            replay.show(step: 0)
            check(replay.shownText == "one", "the replay rebuilds the first step")
            replay.close()

            recorder.deleteHistory()
            check((try? store.entries(for: id))?.isEmpty == true && !recorder.isRecording, "deleting the history removes it and stops recording")

            // A history that cannot be written says so, once.
            let blocker = historyRoot.appendingPathComponent("not-a-folder")
            try "x".write(to: blocker, atomically: true, encoding: .utf8)
            var errors: [String] = []
            let failing = HistoryRecorder(store: HistoryStore(root: blocker.appendingPathComponent("History")), clock: { now })
            failing.onError = { errors.append($0) }
            failing.setRecording(true, fileURL: file, text: "one")
            now = 10; failing.textChanged("one two")
            now = 20; failing.textChanged("one two three")
            check(errors.count == 1, "a history that cannot be saved is reported once, not silently dropped")
            historyDocument.close()
        } catch {
            check(false, "writing history: \(error.localizedDescription)")
        }

        // 13a-9. Compare With shows two documents side by side.
        editor.setText("# Essay\n\nThe sea was wild today.\nGulls overhead.\n")
        let compare = controller.compare(withText: "# Essay\n\nThe sea was calm today.\n", title: "Exercise")
        check(compare.changedLineCount == 2, "the comparison counts changed lines")
        check(compare.headerText.contains("Exercise") && compare.headerText.contains("2 lines changed"), "the comparison names both sides and the count")
        check(compare.leftText.components(separatedBy: "\n").count == compare.rightText.components(separatedBy: "\n").count, "the two sides are aligned row by row")
        compare.close()

        // 13a-10. Editor font and Styled Markdown follow the preferences, and
        // styling never edits the document.
        controller.applyPreferences()
        check(editor.fontChoice == (EditorFontChoice(rawValue: EditorPreferences.editorFont) ?? .jetBrainsMono), "the editor uses the chosen font")
        check(editor.stylesMarkdown == EditorPreferences.styledMarkdown, "Styled Markdown follows its preference")
        let editedBeforeStyling = document.isDocumentEdited
        editor.stylesMarkdown = true
        editor.setText("Plain and **strong** text.\n")
        _ = pump(timeout: 2) { editor.lastAppliedRevision == editor.revision && editor.revision > 0 }
        editor.reparseSynchronously()
        let strongAt = (editor.source as NSString).range(of: "strong").location
        let strongFont = editor.textView.textStorage?.attribute(.font, at: strongAt, effectiveRange: nil) as? NSFont
        let drawnBold = editor.textView.textStorage?.attribute(.strokeWidth, at: strongAt, effectiveRange: nil) != nil
        check(drawnBold || strongFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "strong text is set bold in the editor")
        check(editor.source == "Plain and **strong** text.\n", "styling leaves the text as it is")
        check(document.isDocumentEdited == editedBeforeStyling, "styling does not dirty the document")
        editor.stylesMarkdown = EditorPreferences.styledMarkdown
        if let serif = NSFont(name: "SourceSerif4-Regular", size: 15) {
            let face = StyledFace.make(base: serif, bold: true, italic: true)
            check(NSFontManager.shared.traits(of: face.font).contains(.boldFontMask), "bold italic in Source Serif keeps its bold")
            check(face.font.textTransform.m21 > 0 || NSFontManager.shared.traits(of: face.font).contains(.italicFontMask), "bold italic in Source Serif is slanted")
        }

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

        // 13c-1. Paired lines: a source position lights its preview block and
        // a preview block lights its source, as rendering state only.
        let pairingSource = editor.source as NSString
        let cellLocation = pairingSource.range(of: "| 1 |").location
        let editedBeforePairing = document.isDocumentEdited
        let storageBeforePairing = editor.textView.string
        controller.pairForTesting(editorLocation: cellLocation)
        check(controller.previewHighlightedBlockKind == "table", "a source line lights its preview block")
        controller.pairForTesting(previewBlockAt: 0)
        check(controller.editorPairedRange == NSRange(location: 0, length: 15), "a preview block lights its source")
        _ = pump(timeout: 0.3) { false }
        check(lineIsTinted(editor.textView, sourceLocation: 3), "the lit source is tinted on screen")
        check(editor.textView.string == storageBeforePairing, "pairing does not change the text")
        check(document.isDocumentEdited == editedBeforePairing, "pairing does not dirty the document")
        controller.pairForTesting(previewBlockAt: 99)
        _ = pump(timeout: 0.3) { false }
        check(!lineIsTinted(editor.textView, sourceLocation: 3), "the tint goes when the pointer leaves")
        controller.pairForTesting(editorLocation: (pairingSource.range(of: "\n\n| a").location) + 1)
        check(controller.previewHighlightedBlockKind == nil, "a blank line lights nothing")
        controller.pairForTesting(editorLocation: cellLocation)
        controller.setViewMode(.write)
        check(controller.previewHighlightedBlockKind == nil && controller.editorPairedRange == nil, "leaving Split clears the pairing")
        controller.setViewMode(.split)
        _ = pump(timeout: 2) { controller.previewText.contains("Emoji") }

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

        checkCitations(check)

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

    // MARK: - Citations

    private static let citationBib = """
    @article{silva2020,
      author = {Silva, Ana},
      title = {Lung function at home},
      journal = {Journal of Tests},
      year = {2020}
    }

    """

    private static let citationText = """
    ---
    bibliography: refs.bib
    ---
    # A title

    A claim [@silva2020] in a line.

    The next paragraph.

    """

    /// A window on a document in a new folder that holds `refs.bib`.
    private static func citationDocument(
        text: String,
        folder: URL,
        saved: Bool = true
    ) throws -> (LoomingsDocument, EditorWindowController) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(citationBib.utf8).write(to: folder.appendingPathComponent("refs.bib"))
        let document = LoomingsDocument()
        document.fileType = "net.daringfireball.markdown"
        if saved {
            let url = folder.appendingPathComponent("paper.md")
            try Data(text.utf8).write(to: url)
            document.fileURL = url
        }
        NSDocumentController.shared.addDocument(document)
        document.pendingText = text
        document.makeWindowControllers()
        guard let controller = document.windowControllers.first as? EditorWindowController else {
            throw CocoaError(.featureUnsupported)
        }
        controller.showWindow(nil)
        controller.showsExportStatusSheet = false
        controller.editor.textView.isContinuousSpellCheckingEnabled = false
        return (document, controller)
    }

    private static func closeCitationDocument(_ document: LoomingsDocument) {
        document.updateChangeCount(.changeCleared)
        document.close()
    }

    private static func checkCitations(_ check: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-selftest-citations-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try checkFormattedDocument(check, folder: root.appendingPathComponent("formatted"))
            try checkPlainDocument(check, folder: root.appendingPathComponent("plain"))
            try checkDocumentsWithNoFolder(check, folder: root.appendingPathComponent("no-folder"))
            try checkStaleReports(check, folder: root.appendingPathComponent("stale"))
            try checkNoFlash(check, folder: root.appendingPathComponent("flash"))
            try checkExportLimit(check, folder: root.appendingPathComponent("limit"))
            try checkExportNotes(check, folder: root.appendingPathComponent("notes"))
            try checkExportAfterClose(check, folder: root.appendingPathComponent("closed"))
            try checkPrintOrder(check, folder: root.appendingPathComponent("print"))
            try checkPrintPanel(check, folder: root.appendingPathComponent("panel"))
            try checkInsertWithSlowEngine(check, folder: root.appendingPathComponent("insert"))
            try checkCitationMarks(check, folder: root.appendingPathComponent("marks"))
            try checkNotesMerge(check, folder: root.appendingPathComponent("merge"))
            try checkMissingFileNote(check, folder: root.appendingPathComponent("missing"))
            try inRunningApp { try checkCompletionList(check, folder: root.appendingPathComponent("completion")) }
            checkReferencesMenuItems(check)
            try checkReferenceChoices(check, folder: root.appendingPathComponent("choices/paper"))
            try checkReferenceRefusals(check, folder: root.appendingPathComponent("refusals"))
            try checkReferencesColumn(check, folder: root.appendingPathComponent("column"))
            try checkReferenceInsertion(check, folder: root.appendingPathComponent("insertion"))
            try checkShareLinks(check, folder: root.appendingPathComponent("share"))
            try checkShareStyle(check, folder: root.appendingPathComponent("share-style"))
            try checkShareOnPaper(check, folder: root.appendingPathComponent("share-paper"))
            try checkShareFallback(check, folder: root.appendingPathComponent("share-fallback"))
            try checkSharedPaths(check, folder: root.appendingPathComponent("share-paths"))
        } catch {
            check(false, "citation setup (\(error))")
        }
    }

    // MARK: - Share links with citations

    /// A window on the text of a share link, as Open Share Link makes it.
    private static func sharedDocument(text: String) throws -> (LoomingsDocument, EditorWindowController) {
        let document = LoomingsDocument.shared(text: text)
        document.fileType = "net.daringfireball.markdown"
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.windowControllers.first as? EditorWindowController else {
            throw CocoaError(.featureUnsupported)
        }
        controller.showWindow(nil)
        controller.showsExportStatusSheet = false
        return (document, controller)
    }

    /// The link that Copy Share Link gives for the controller's document.
    private static func copiedLink(_ controller: EditorWindowController) throws -> SharePayload {
        NSPasteboard.general.clearContents()
        controller.copyShareLink(nil)
        guard pump(timeout: 15, until: { NSPasteboard.general.string(forType: .string) != nil }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try ShareLink.parse(string: NSPasteboard.general.string(forType: .string) ?? "")
    }

    private static func checkShareLinks(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: citationText, folder: folder)
        defer { closeCitationDocument(document) }
        let payload = try copiedLink(controller)
        check(payload.text.contains("references: [{") && payload.text.contains("Lung function at home"), "the link has the cited entry")
        check(payload.text.contains("bibliography: refs.bib"), "the link keeps the bibliography line")
        check(controller.editor.source == citationText, "the writer's document does not change")
        check(controller.shareStatus == nil, "a link with a bundled style has no status")
        check(document.cameFromShareLink == false, "a document from a file is not a shared document")

        controller.showQRCodeForTesting()
        check(pump(timeout: 15) { controller.qrSourceForTesting == payload.text }, "the QR code has the same text as the link")
        controller.window?.makeKeyAndOrderFront(nil)

        let (received, reader) = try sharedDocument(text: payload.text)
        defer { closeCitationDocument(received) }
        let reported = pump(timeout: 15) { reader.citations.report(for: payload.text) != nil }
        check(reported, "a shared document gets a report")
        let report = reader.citations.report(for: payload.text)
        check(report?.citations.first?.markdown == "(Silva 2020)", "the reader sees the citation with no file")
        check(report?.bibliography.first?.contains("Silva") == true, "the reader sees the reference list")
        check(report?.notes.isEmpty == true, "an absent bibliography gives no note when the link holds the entries")
    }

    private static func checkShareStyle(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = citationText.replacingOccurrences(of: "bibliography: refs.bib", with: "bibliography: refs.bib\ncsl: own-journal.csl")
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        let payload = try copiedLink(controller)
        check(
            controller.shareStatus == "The link carries the citations; the style own-journal.csl stays here, so the reader sees the default style.",
            "the status says that an uploaded style stays here"
        )
        check(payload.text.contains("csl: own-journal.csl"), "the shared text keeps the name of the style")

        let (received, reader) = try sharedDocument(text: payload.text)
        defer { closeCitationDocument(received) }
        check(pump(timeout: 15) { reader.citations.report(for: payload.text) != nil }, "a shared document with another style gets a report")
        let report = reader.citations.report(for: payload.text)
        check(report?.citations.first?.markdown == "(Silva 2020)", "the reader gets the default style")
        check(
            report?.notes.last?.message == "The style own-journal.csl was not found. The default style is chicago-author-date.",
            "the reader gets a note about the style"
        )
    }

    private static func checkShareOnPaper(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: citationText, folder: folder)
        defer { closeCitationDocument(document) }
        var printed: HandoutTextView?
        controller.printHookForTesting = { printed = $0 }
        controller.printPreview(nil)
        check(pump(timeout: 15) { printed != nil }, "the handout prints")
        check(printed?.sharedSource.contains("references: [{") == true, "the handout's QR code has the cited entries")
        check(printed?.string.contains("(Silva 2020)") == true, "the handout has the formatted citation")
        check(controller.editor.source == citationText, "the print does not change the document")
    }

    private static func checkShareFallback(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        let status = "The citations are not ready; the link has only the text."

        controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 0, shareDelay: 1))
        controller.citations.exportLimit = 0.2
        controller.editor.setText(citationText)
        let late = try copiedLink(controller)
        check(late.text == citationText, "a late share falls back to the plain text")
        check(controller.shareStatus == status, "a late share says so")
        let link = NSPasteboard.general.string(forType: .string)
        _ = pump(timeout: 1.2) { false }
        check(NSPasteboard.general.string(forType: .string) == link, "a late answer does not change the pasteboard")

        controller.citations.useEngineForTesting(try FailingCitationEngine())
        let failed = try copiedLink(controller)
        check(failed.text == citationText, "a failed share falls back to the plain text")
        check(controller.shareStatus == status, "a failed share says so")
    }

    private static func checkSharedPaths(_ check: (Bool, String) -> Void, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outside = folder.appendingPathComponent("outside.bib")
        try Data(citationBib.utf8).write(to: outside)
        let text = citationText.replacingOccurrences(of: "bibliography: refs.bib", with: "bibliography: \(outside.path)")
        let note = "This shared document names a file on this computer. It stays unread until you save the document."

        let (document, controller) = try sharedDocument(text: text)
        defer { closeCitationDocument(document) }
        check(pump(timeout: 15) { controller.citations.report(for: text) != nil }, "a shared document with a path gets a report")
        var report = controller.citations.report(for: text)
        check(report?.notes.first?.message == note, "a shared document says that a path stays unread")
        check(report?.citations.first?.markdown != "(Silva 2020)", "a shared document does not read an absolute path")

        let archive = NSKeyedArchiver(requiringSecureCoding: false)
        document.encodeRestorableState(with: archive)
        let restored = LoomingsDocument()
        restored.restoreState(with: try NSKeyedUnarchiver(forReadingFrom: archive.encodedData))
        check(restored.cameFromShareLink, "a restored document stays a shared document")

        var saved = false
        document.save(to: folder.appendingPathComponent("kept.md"), ofType: "net.daringfireball.markdown", for: .saveAsOperation) { _ in saved = true }
        check(pump(timeout: 5) { saved }, "the shared document saves")
        check(document.cameFromShareLink == false, "a save ends the mark")
        let read = pump(timeout: 15) { controller.citations.report(for: text)?.citations.first?.markdown == "(Silva 2020)" }
        check(read, "a saved document reads its paths")
        report = controller.citations.report(for: text)
        check(report?.notes.contains { $0.message == note } == false, "the note goes after the save")
    }

    private static func checkFormattedDocument(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: citationText, folder: folder)
        defer { closeCitationDocument(document) }
        controller.setViewMode(.split)
        let shown = pump(timeout: 15) { controller.previewText.contains("(Silva 2020)") }
        check(shown, "a document with refs.bib next to it shows a formatted citation")
        check(!controller.previewText.contains("[@silva2020]"), "the preview has no literal key")
        check(controller.previewText.contains("Lung Function at Home"), "the preview has the reference list")
        check(controller.editor.source == citationText, "the document text does not change")
        check(controller.citations.enginesCreated == 1, "a document with the key has one engine")

        // The citation changes the length of its line: pairing goes by line.
        let text = citationText as NSString
        let next = text.range(of: "The next paragraph.")
        controller.pairForTesting(editorLocation: next.location + 2)
        check(controller.previewHighlightedBlockKind == "paragraph", "a line after a citation pairs with its block")
        let blocks = controller.previewBlockCountForTesting
        controller.pairForTesting(previewBlockAt: blocks - 1)
        check(controller.editorPairedRange == nil, "the reference list pairs with no source")
        controller.pairForTesting(previewBlockAt: blocks - 2)
        check(controller.editorPairedRange?.location == next.location, "a block after a citation pairs with its source line")

        controller.citations.exportLimit = 10
        var written = false
        let htmlURL = folder.appendingPathComponent("out.html")
        controller.exportHTML(to: htmlURL) { written = true }
        check(pump(timeout: 5) { written }, "the HTML export ends")
        let html = (try? String(contentsOf: htmlURL, encoding: .utf8)) ?? ""
        check(html.contains("(Silva 2020)") && !html.contains("[@silva2020]"), "the HTML export has the formatted citation")
        check(controller.exportStatus == nil, "the export gives no status when the report is ready")
        let pdf = PDFDocument(data: controller.renderedPDFForTesting())?.string ?? ""
        check(pdf.contains("(Silva 2020)"), "the handout has the formatted citation")

        // A change on disk is read on activation.
        let renamed = citationBib.replacingOccurrences(of: "Silva, Ana", with: "Silva, Beatriz Longname")
        try Data(renamed.utf8).write(to: folder.appendingPathComponent("refs.bib"))
        document.checkCitationFiles()
        check(pump(timeout: 15) { controller.previewText.contains("Silva, Beatriz Longname") }, "a changed bibliography is read again on activation")

        try FileManager.default.removeItem(at: folder.appendingPathComponent("refs.bib"))
        document.checkCitationFiles()
        let gone = pump(timeout: 15) {
            controller.citations.report(for: citationText)?.notes.contains { $0.message == "The file refs.bib is missing." } == true
        }
        check(gone, "a deleted bibliography gives a file note on activation")
    }

    private static func checkPlainDocument(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = "# Plain\n\nA line with [@silva2020].\n"
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        controller.setViewMode(.split)
        check(pump { controller.previewText.contains("[@silva2020]") }, "with no key the preview shows the source")
        check(controller.previewInputForTesting == text, "with no key the source reaches the renderer unchanged")
        _ = pump(timeout: 0.6) { false }
        check(controller.citations.enginesCreated == 0, "a document with no key has no engine")
        check(controller.citations.report(for: text) == nil, "a document with no key has no report")

        // A key that is outside the frontmatter passes the gate. JS decides.
        let late = "---\ntitle: T\n---\nbibliography: x\n\nA line with [@silva2020].\n"
        controller.editor.setText(late)
        check(pump(timeout: 15) { controller.citations.report(for: late) != nil }, "the gate lets a doubtful text through")
        check(controller.citations.report(for: late)?.markdownSource == late, "the citation code leaves that text as it is")
    }

    private static func checkDocumentsWithNoFolder(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: citationText, folder: folder, saved: false)
        defer { closeCitationDocument(document) }
        let reported = pump(timeout: 15) { controller.citations.report(for: citationText) != nil }
        check(reported, "an untitled document gets a report")
        let notes = controller.citations.report(for: citationText)?.notes.map(\.message) ?? []
        check(notes.first?.contains("no folder") == true, "an untitled document says that it has no folder")

        // Saving gives the document a folder, so the file is found.
        var saved = false
        document.save(
            to: folder.appendingPathComponent("saved.md"),
            ofType: "net.daringfireball.markdown",
            for: .saveAsOperation
        ) { _ in saved = true }
        check(pump { saved }, "the untitled document saves")
        let found = pump(timeout: 15) {
            controller.citations.report(for: citationText)?.citations.first?.markdown == "(Silva 2020)"
        }
        check(found, "saving next to refs.bib formats the citation")

        let shelf = LocalShelf(root: folder.appendingPathComponent("shelf", isDirectory: true))
        let entry = try shelf.create(title: "Shelved", data: Data(citationText.utf8), fileExtension: "md")
        let shelved = LoomingsDocument()
        shelved.shelf = shelf
        shelved.fileURL = shelf.contentURL(for: entry)
        check(shelved.citationDocumentURL == nil, "a shelf document has no folder for citations")
    }

    private static func checkStaleReports(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        let engine = try SlowCitationEngine(delay: 0.6)
        let citations = CitationController(makeEngine: { engine })
        var delivered: [String] = []
        citations.onReport = { delivered.append($0.markdownSource) }

        let url = folder.appendingPathComponent("paper.md")
        let older = citationText + "Older text.\n"
        let newer = citationText + "Newer text.\n"
        citations.update(source: older, documentURL: url)
        check(pump { engine.analyses > 0 }, "the first report starts")
        citations.update(source: newer, documentURL: url)
        check(pump(timeout: 15) { citations.report(for: newer) != nil }, "the newest report arrives")
        _ = pump(timeout: 0.1) { false }
        check(citations.droppedReports == 1, "a stale report is dropped")
        check(delivered.count == 1 && delivered[0].contains("Newer text."), "only the newest report is delivered")
        check(citations.report(for: older) == nil, "the stale report is not kept")
        citations.close()
        _ = controller
    }

    private static func checkNoFlash(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 0.5))
        controller.setViewMode(.split)
        controller.editor.setText(citationText)
        check(pump(timeout: 15) { controller.previewText.contains("(Silva 2020)") }, "the slow engine gives a report")

        controller.editor.textView.setSelectedRange(NSRange(location: (citationText as NSString).length, length: 0))
        let renders = controller.previewRendersForTesting
        controller.editor.textView.insertText("New words.", replacementRange: controller.editor.textView.selectedRange())
        // Longer than the preview's own delay, shorter than the report.
        _ = pump(timeout: 0.5) { false }
        check(controller.previewRendersForTesting == renders, "an edit keeps the last preview while the report is on the way")
        check(controller.previewText.contains("(Silva 2020)"), "literal keys do not flash after an edit")
        check(pump(timeout: 15) { controller.previewText.contains("New words.") }, "the report brings the new text")
        check(controller.previewText.contains("(Silva 2020)"), "the new preview has the formatted citation")
    }

    private static func checkExportLimit(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 1))
        controller.citations.exportLimit = 0.1
        controller.editor.setText(citationText)
        let start = Date()
        var written = false
        let url = folder.appendingPathComponent("late.html")
        controller.exportHTML(to: url) { written = true }
        check(!written, "the export does not block the main thread")
        check(pump { written }, "the export ends at the limit")
        check(Date().timeIntervalSince(start) < 1, "the export ends before the slow report")
        let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        check(html.contains("[@silva2020]"), "the late export has the literal key")
        check(controller.exportStatus?.contains("not ready") == true, "the late export gives a clear status")
        check(pump(timeout: 15) { controller.citations.report(for: citationText) != nil }, "the report still arrives")
    }

    private static func checkExportNotes(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: citationText, folder: folder)
        defer { closeCitationDocument(document) }
        check(pump(timeout: 15) { controller.citations.report(for: citationText) != nil }, "the notes document has a report")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("refs.bib"))
        document.checkCitationFiles()
        let noted = pump(timeout: 15) {
            controller.citations.report(for: citationText)?.notes.isEmpty == false
        }
        check(noted, "the deleted file gives a note")
        var written = false
        controller.exportHTML(to: folder.appendingPathComponent("noted.html")) { written = true }
        check(pump { written }, "the export with a note ends")
        check(controller.exportStatus?.contains("refs.bib is missing") == true, "a report with a file note gives an export status")

        let failed = try citationDocument(text: citationText, folder: folder.appendingPathComponent("failed"))
        defer { closeCitationDocument(failed.0) }
        failed.1.citations.useEngineForTesting(try FailingCitationEngine())
        var done = false
        failed.1.exportHTML(to: folder.appendingPathComponent("failed.html")) { done = true }
        check(pump(timeout: 15) { done }, "the export of a failed report ends")
        check(failed.1.exportStatus?.contains("The citation code failed") == true, "a failed report gives an export status")
    }

    /// A window that closes during the wait still writes the file. No test
    /// variable may hold the window controller past the close.
    private static func checkExportAfterClose(_ check: (Bool, String) -> Void, folder: URL) throws {
        let url = folder.appendingPathComponent("closed.html")
        var written = false
        weak var closed: EditorWindowController?
        try autoreleasepool {
            let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
            closed = controller
            controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 0.5))
            controller.editor.setText(citationText)
            controller.exportHTML(to: url) { written = true }
            closeCitationDocument(document)
        }
        check(pump(timeout: 15) { written }, "an export ends after its window closes")
        let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        check(html.contains("(Silva 2020)"), "the export after a close has the formatted citation")
        check(pump { closed == nil }, "the closed window is released after its export")
    }

    /// At the limit the status comes first. The page and the share link come
    /// from one text, also when the writer types during the wait.
    private static func checkPrintOrder(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 1))
        controller.citations.exportLimit = 0.2
        controller.editor.setText(citationText)
        var statusAtPrint: String?
        var printed: HandoutTextView?
        controller.printHookForTesting = { view in
            statusAtPrint = controller.exportStatus
            printed = view
        }
        controller.printPreview(nil)
        controller.editor.setText(citationText + "Typed during the wait.\n")
        check(pump { printed != nil }, "the print ends at the limit")
        check(statusAtPrint?.contains("not ready") == true, "the status comes before the print panel")
        check(printed?.string.contains("[@silva2020]") == true, "the late print has the literal key")
        check(printed?.sharedSource == citationText, "the share link has the same text as the page")
        check(printed?.string.contains("Typed during the wait.") == false, "the page has the text from the start of the wait")
    }

    /// The print panel opens from a main queue block. As a sheet it leaves the
    /// main queue free. A nested modal run would hold every later block.
    private static func checkPrintPanel(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 0.1))
        controller.editor.setText(citationText)
        controller.printPreview(nil)
        guard let window = controller.window else { return }
        let opened = pump(timeout: 15) { window.attachedSheet != nil }
        check(opened, "the print panel opens as a sheet from the wait path")
        var ran = false
        DispatchQueue.main.async { ran = true }
        check(pump(timeout: 2) { ran }, "the main queue runs while the print panel is open")
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        check(pump(timeout: 5) { window.attachedSheet == nil }, "the print panel closes")
    }

    /// Runs the run loop, and gives the longest single turn in milliseconds.
    private static func longestTurn(_ seconds: TimeInterval) -> Double {
        let deadline = Date().addingTimeInterval(seconds)
        var longest = 0.0
        while Date() < deadline {
            let start = DispatchTime.now().uptimeNanoseconds
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            longest = max(longest, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        return longest
    }

    /// Each sample is one `insertText` call. Bursts leave pauses, so the slow
    /// engine is at work during the later bursts. A wait on the main thread
    /// falls between two calls, so the longest run loop turn shows it.
    private static func typing(_ controller: EditorWindowController) -> (insertP95: Double, longestTurn: Double) {
        let textView = controller.editor.textView
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        var samples: [Double] = []
        var turn = 0.0
        for _ in 0..<3 {
            for _ in 0..<40 {
                let start = DispatchTime.now().uptimeNanoseconds
                textView.insertText("x", replacementRange: textView.selectedRange())
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                turn = max(turn, longestTurn(0.002))
            }
            turn = max(turn, longestTurn(0.5))
        }
        samples.sort()
        return (samples[Int(Double(samples.count - 1) * 0.95)], turn)
    }

    private static func checkInsertWithSlowEngine(_ check: (Bool, String) -> Void, folder: URL) throws {
        let body = String(repeating: "A line of text for the insert measure.\n\n", count: 200)
        let (plain, plainController) = try citationDocument(text: body, folder: folder.appendingPathComponent("plain"))
        plainController.setViewMode(.split)
        check(pump { plainController.editor.lastAppliedRevision == plainController.editor.revision }, "the plain document parses")
        _ = typing(plainController)
        let baseline = typing(plainController)
        closeCitationDocument(plain)

        let (cited, citedController) = try citationDocument(text: "Empty.\n", folder: folder.appendingPathComponent("cited"))
        defer { closeCitationDocument(cited) }
        let engine = try SlowCitationEngine(delay: 0.7)
        citedController.citations.useEngineForTesting(engine)
        citedController.setViewMode(.split)
        citedController.editor.setText(citationText + body)
        check(pump(timeout: 15) { citedController.citations.report(for: citationText + body) != nil }, "the slow document has a report")
        _ = typing(citedController)
        let slow = typing(citedController)
        let times = [baseline.insertP95, slow.insertP95, baseline.longestTurn, slow.longestTurn].map { String(format: "%.2f", $0) }
        print("insert p95: \(times[0]) ms plain, \(times[1]) ms with a slow engine; longest turn: \(times[2]) ms, \(times[3]) ms")
        check(engine.analyses >= 3, "the slow engine worked during the typing")
        check(slow.insertP95 <= max(baseline.insertP95 * 1.5, baseline.insertP95 + 4), "Insert p95 stays the same with a slow engine")
        check(slow.longestTurn < 350, "the main thread does not wait for a slow engine")
    }

    private static let markText = """
    ---
    bibliography: refs.bib
    ---
    A claim [@silva2020] and [@nobody] end.

    Next line.

    """

    private static func checkCitationMarks(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: markText, folder: folder)
        defer { closeCitationDocument(document) }
        let editor = controller.editor
        let textView = editor.textView
        let revision = editor.revision
        check(pump(timeout: 15) { editor.citationRanges.count == 2 }, "a report gives the editor its citations")
        let text = markText as NSString
        let known = text.range(of: "[@silva2020]")
        let unknown = text.range(of: "[@nobody]")
        check(textView.decorations(for: "citations").map(\.range) == [unknown], "an unknown key has a squiggle")
        check(textView.decorations(for: "notes").isEmpty, "the squiggle does not use the checker's layer")
        check(editor.citationKeys.map(\.key) == ["silva2020"], "the library reaches the editor")

        check(editor.revision == revision && !document.isDocumentEdited, "marks do not edit the document")

        check(squigglePainted(textView, range: unknown), "the squiggle reaches the screen")

        // An edit before the marks moves them at once.
        textView.setSelectedRange(NSRange(location: text.range(of: "A claim").location, length: 0))
        textView.insertText("New. ", replacementRange: textView.selectedRange())
        check(
            textView.decorations(for: "citations").map(\.range) == [NSRange(location: unknown.location + 5, length: unknown.length)],
            "a squiggle follows an edit before it"
        )

        // One Undo takes back the edit, and the mark goes back with it.
        textView.undoManager?.undo()
        check(editor.source == markText, "Undo restores the text")
        check(textView.decorations(for: "citations").map(\.range) == [unknown], "the squiggle follows Undo")

        // An edit in a mark drops it. The next report brings it back.
        textView.insertText("x", replacementRange: NSRange(location: unknown.location + 3, length: 0))
        check(textView.decorations(for: "citations").isEmpty, "an edit in a mark drops the mark")
        textView.undoManager?.undo()
        check(editor.source == markText, "Undo restores the key")
        check(
            pump(timeout: 15) { textView.decorations(for: "citations").map(\.range) == [unknown] },
            "the next report brings the mark back"
        )

        // No citation keys: no marks and no list.
        editor.replace(range: text.range(of: "bibliography: refs.bib"), with: "title: x")
        check(pump(timeout: 5) { editor.citationRanges.isEmpty && editor.citationKeys.isEmpty }, "a document with no bibliography has no marks")
        check(controller.citations.latestResult == nil, "the report goes with the bibliography")
        check(controller.noteMessagesForTesting.isEmpty, "a document with no bibliography has no citation notes")
        check(textView.textStorage?.delegate === editor, "the editor stays the delegate of the text storage in a window")
    }

    /// True when the row under `range` differs with and without its squiggle.
    private static func squigglePainted(_ textView: EditorTextView, range: NSRange) -> Bool {
        guard let frame = textView.segmentFrames(for: range).first else { return false }
        let row = NSRect(x: frame.minX, y: frame.maxY - 4, width: frame.width, height: 4)
        func image() -> Data? {
            guard let bitmap = textView.bitmapImageRepForCachingDisplay(in: row) else { return nil }
            textView.cacheDisplay(in: row, to: bitmap)
            return bitmap.tiffRepresentation
        }
        let marked = image()
        let decorations = textView.decorations(for: "citations")
        textView.setDecorations([], for: "citations")
        let plain = image()
        textView.setDecorations(decorations, for: "citations")
        return marked != nil && marked != plain
    }

    private static func checkNotesMerge(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = markText + "####No space here\n"
        let (document, controller) = try citationDocument(text: "Empty.\n", folder: folder)
        defer { closeCitationDocument(document) }
        controller.citations.useEngineForTesting(try SlowCitationEngine(delay: 0.5))
        let editor = controller.editor
        editor.setText(text)
        editor.textView.window?.makeFirstResponder(editor.textView)
        editor.textView.insertText("", replacementRange: NSRange(location: 0, length: 0))
        check(pump(timeout: 5) { !controller.notesForTesting.isEmpty }, "the checker's notes come first")
        let lint = controller.notesForTesting.count
        check(controller.statusNotesTitleForTesting == (lint == 1 ? "1 note" : "\(lint) notes"), "the count waits for no report")

        check(pump(timeout: 15) { controller.citations.report(for: text) != nil }, "the report comes late")
        let total = lint + 1
        check(controller.statusNotesTitleForTesting == "\(total) notes", "the late report adds to the count")
        check(controller.notesForTesting.count == lint, "the late report keeps the checker's notes")
        let messages = controller.noteMessagesForTesting
        check(messages.count == total, "the list has both kinds of note")
        check(messages.first?.contains("nobody") == true, "the notes go by place: \(messages)")

        controller.showNotesForTesting()
        check(controller.isNotesPopoverShownForTesting, "the merged list opens")
        check(controller.noteButtonsForTesting.filter { $0.hasPrefix("Go to line") }.count == total, "each note with a place can go to its line")
        controller.closeNotesForTesting()
    }

    private static func checkMissingFileNote(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = """
        ---
        bibliography: lost.bib
        ---
        A claim [@silva2020].

        """
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        let editor = controller.editor
        check(pump(timeout: 15) { controller.citations.report(for: text) != nil }, "a document with a missing file has a report")
        check(controller.noteMessagesForTesting.contains("The file lost.bib is missing."), "the missing file is a note")
        controller.showNotesForTesting()
        let buttons = controller.noteButtonsForTesting
        check(buttons.contains("Choose lost.bib\u{2026}"), "a missing file has an action")
        let fileRows = buttons.filter { $0.hasPrefix("Choose") }.count
        check(fileRows == 1, "one action for one missing file")
        check(buttons.count == fileRows + 1, "a note about a file has no Go to line: \(buttons)")
        controller.closeNotesForTesting()

        // The panel gives a file: one edit, one Undo.
        let chosen = folder.appendingPathComponent("refs.bib")
        let before = editor.revision
        controller.useCitationFile(chosen, for: "lost.bib")
        check(pump(timeout: 5) { editor.source.contains("bibliography: refs.bib") }, "the chosen file goes in the frontmatter")
        check(editor.source.hasSuffix("A claim [@silva2020].\n"), "the body stays")
        check(editor.revision == before + 1, "the choice is one edit")
        check(
            pump(timeout: 15) { controller.citations.report(for: editor.source)?.citations.first?.markdown == "(Silva 2020)" },
            "the citation formats with the chosen file"
        )
        check(editor.textView.undoManager?.canUndo == true, "the choice can be undone")
        editor.textView.undoManager?.undo()
        check(editor.source == text, "one Undo takes the choice back")
        editor.textView.undoManager?.redo()
        check(editor.source.contains("bibliography: refs.bib"), "Redo puts it back")
    }

    // MARK: - References

    private static let moreBib = """
    @article{jacome2021,
      author = {J\\'{a}come, Cristina},
      title = {Sa\\'{u}de em casa},
      journal = {Journal of Tests},
      year = {2021}
    }

    """

    private static func referencesMenu() -> NSMenu? {
        AppDelegate().makeMainMenu().items.first { $0.submenu?.title == "References" }?.submenu
    }

    private static func item(_ menu: NSMenu?, _ title: String) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.title == title { return item }
            if let found = Self.item(item.submenu, title) { return found }
        }
        return nil
    }

    /// True when a window with this responder chain handles the action.
    private static func handles(_ window: NSWindow, _ action: Selector) -> Bool {
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if current.responds(to: action) { return true }
            responder = current.nextResponder
        }
        return (window.delegate as AnyObject?)?.responds(to: action) ?? false
    }

    private static func checkReferencesMenuItems(_ check: (Bool, String) -> Void) {
        let titles = AppDelegate().makeMainMenu().items.compactMap(\.submenu?.title)
        let format = titles.firstIndex(of: "Format") ?? -1
        check(titles.indices.contains(format + 2) && titles[format + 1] == "References" && titles[format + 2] == "Theme", "References is between Format and Theme: \(titles)")
        let menu = referencesMenu()
        check(
            menu?.items.map(\.title) == ["Choose Bibliography\u{2026}", "Citation Style", "Language", "", "Show References"],
            "the References menu has its items"
        )
        let styles = item(menu, "Citation Style")?.submenu
        check(styles?.items.first?.title == "Chicago (author-date)", "the style titles come from the shared list")
        check(styles?.items.count == 7, "five styles, a separator and a file")
        check(styles?.items.last?.title == "Choose File\u{2026}", "the file comes after the styles")
        check(
            item(menu, "Language")?.submenu?.items.compactMap { $0.representedObject as? String } == ["en-US", "en-GB", "pt-PT", "es-ES"],
            "the menu has the four languages"
        )
        check(
            menu?.items.filter { $0.action != nil && !$0.hasSubmenu }.allSatisfy { $0.target == nil } == true,
            "the items go to the first responder"
        )
    }

    private static func checkReferenceChoices(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = "Plain text.\n"
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        let editor = controller.editor
        let undo = editor.textView.undoManager
        let menu = referencesMenu()

        // The first choice makes the frontmatter: one edit, one Undo.
        let caret = (text as NSString).range(of: "text").location
        editor.textView.setSelectedRange(NSRange(location: caret, length: 0))
        let before = editor.revision
        controller.addBibliography(folder.appendingPathComponent("refs.bib"))
        check(pump(timeout: 15) { editor.source == "---\nbibliography: refs.bib\n---\nPlain text.\n" }, "a bibliography makes the frontmatter: \(editor.source)")
        check(editor.revision == before + 1, "the choice is one edit")
        let shifted = (editor.source as NSString).range(of: "text").location
        check(editor.textView.selectedRange().location == shifted, "the caret stays on its word")
        undo?.undo()
        check(editor.source == text, "one Undo takes the bibliography back")
        undo?.redo()
        check(editor.source.hasPrefix("---\nbibliography: refs.bib\n"), "Redo puts the bibliography back")

        // A file in a folder next to the document's folder.
        let shared = folder.deletingLastPathComponent().appendingPathComponent("shared/more.bib")
        try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(moreBib.utf8).write(to: shared)
        controller.addBibliography(shared)
        let flow = "bibliography: [refs.bib, ../shared/more.bib]\n"
        check(pump(timeout: 5) { editor.source.contains(flow) }, "a second file gives a flow list: \(editor.source)")
        let read = pump(timeout: 15) {
            controller.citations.report(for: editor.source)?.library.map(\.key).sorted() == ["jacome2021", "silva2020"]
        }
        check(read, "the citation code reads a path with ../")
        undo?.undo()
        check(editor.source.contains("bibliography: refs.bib\n"), "one Undo takes the second file back")
        undo?.redo()
        let same = editor.source
        controller.addBibliography(shared)
        _ = pump(timeout: 0.5) { false }
        check(editor.source == same, "a file in the list changes nothing")

        // The marks of the menu follow the text.
        var ready = false
        controller.refreshReferenceChoices { ready = true }
        check(pump(timeout: 5) { ready }, "the menu gets its marks")
        let apa = item(menu, "APA")
        let chicago = item(menu, "Chicago (author-date)")
        let portuguese = item(menu, "Portugu\u{EA}s (Portugal)")
        let english = item(menu, "English (US)")
        func validate(_ item: NSMenuItem?) -> Bool { item.map(controller.validateMenuItem) ?? false }
        check(validate(chicago) && chicago?.state == .on, "the default style has the mark")
        check(validate(apa) && apa?.state == .off, "another style has no mark")
        check(validate(english) && english?.state == .on, "the default language has the mark")

        // A choice that is on writes nothing.
        let unchanged = editor.source
        if let chicago { controller.chooseBundledStyle(chicago) }
        _ = pump(timeout: 0.5) { false }
        check(editor.source == unchanged, "the style that is on writes nothing")

        if let apa { controller.chooseBundledStyle(apa) }
        check(pump(timeout: 5) { editor.source.contains("csl: apa\n") }, "a bundled style goes in the frontmatter")
        undo?.undo()
        check(editor.source == unchanged, "one Undo takes the style back")
        undo?.redo()
        if let portuguese { controller.chooseLanguage(portuguese) }
        check(pump(timeout: 5) { editor.source.contains("lang: pt-PT\n") }, "a language goes in the frontmatter")
        ready = false
        controller.refreshReferenceChoices { ready = true }
        check(pump(timeout: 5) { ready }, "the menu gets the new marks")
        check(validate(apa) && apa?.state == .on, "the chosen style has the mark")
        check(validate(portuguese) && portuguese?.state == .on, "the chosen language has the mark")
        check(validate(chicago) && chicago?.state == .off, "the mark leaves the old style")

        // An own style file, in the folder.
        let own = folder.appendingPathComponent("own.csl")
        try FileManager.default.copyItem(at: bundledStyle("apa"), to: own)
        controller.useStyleFile(own)
        check(pump(timeout: 5) { editor.source.contains("csl: own.csl\n") }, "a style file goes in the frontmatter")
        ready = false
        controller.refreshReferenceChoices { ready = true }
        check(pump(timeout: 5) { ready }, "the menu gets the marks of the file")
        let file = item(menu, "Choose File\u{2026}")
        check(validate(file) && file?.state == .on, "a style file marks Choose File")
        check(validate(apa) && apa?.state == .off, "a style file takes the mark from the bundled styles")

        // A path with the name of a bundled style is a file.
        let named = folder.appendingPathComponent("own/apa.csl")
        try FileManager.default.createDirectory(at: named.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundledStyle("apa"), to: named)
        controller.useStyleFile(named)
        check(pump(timeout: 5) { editor.source.contains("csl: own/apa.csl\n") }, "a style file in a folder goes in the frontmatter")
        ready = false
        controller.refreshReferenceChoices { ready = true }
        check(pump(timeout: 5) { ready }, "the menu gets the marks of that file")
        check(validate(apa) && apa?.state == .off, "a path that ends in apa.csl does not mark APA")

        // A document with no folder gets an absolute path.
        let (untitled, untitledController) = try citationDocument(text: "Text.\n", folder: folder.appendingPathComponent("untitled"), saved: false)
        defer { closeCitationDocument(untitled) }
        let path = folder.appendingPathComponent("refs.bib")
        untitledController.addBibliography(path)
        check(
            pump(timeout: 15) { untitledController.editor.source.contains("bibliography: /") && untitledController.editor.source.contains("/refs.bib\n") },
            "an untitled document gets an absolute path"
        )
    }

    private static func bundledStyle(_ id: String) -> URL {
        (Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")).appendingPathComponent("Citations/styles/\(id).csl")
    }

    private static func dependentStyle(parent: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" default-locale="en-US">
          <info>
            <title>A journal</title>
            <id>http://www.zotero.org/styles/a-journal</id>
            <link href="http://www.zotero.org/styles/\(parent)" rel="independent-parent"/>
          </info>
        </style>

        """
    }

    /// The sheet shows, says `reason`, and nothing is written.
    private static func checkRefusal(
        _ check: (Bool, String) -> Void,
        _ controller: EditorWindowController,
        title: String,
        reason: String,
        _ action: () -> Void
    ) {
        guard let window = controller.window else { return }
        let before = controller.editor.source
        action()
        check(pump(timeout: 15) { window.attachedSheet != nil }, "a sheet shows: \(title)")
        check(controller.choiceAlertForTesting?.messageText == title, "the sheet has its title: \(title)")
        let text = controller.choiceAlertForTesting?.informativeText ?? ""
        check(text.contains(reason), "the sheet says why: \(text)")
        check(controller.editor.source == before, "nothing is written: \(title)")
        let item = NSMenuItem(title: "Bibliography", action: #selector(EditorWindowController.chooseBibliography(_:)), keyEquivalent: "")
        check(!controller.validateMenuItem(item), "the menu waits for the sheet")
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
        check(pump(timeout: 5) { window.attachedSheet == nil }, "the sheet closes")
        check(controller.validateMenuItem(item), "the menu works after the sheet")
    }

    private static func checkReferenceRefusals(_ check: (Bool, String) -> Void, folder: URL) throws {
        let (document, controller) = try citationDocument(text: "Text.\n", folder: folder)
        defer { closeCitationDocument(document) }

        let orphan = folder.appendingPathComponent("orphan.csl")
        try Data(dependentStyle(parent: "absent-parent").utf8).write(to: orphan)
        checkRefusal(check, controller, title: "This style cannot be used.", reason: "absent-parent") {
            controller.useStyleFile(orphan)
        }

        let broken = folder.appendingPathComponent("broken.csl")
        try Data("not a style".utf8).write(to: broken)
        checkRefusal(check, controller, title: "This style cannot be used.", reason: "not valid CSL") {
            controller.useStyleFile(broken)
        }

        let child = folder.appendingPathComponent("child.csl")
        try Data(dependentStyle(parent: "apa").utf8).write(to: child)
        controller.useStyleFile(child)
        check(pump(timeout: 5) { controller.editor.source.contains("csl: child.csl\n") }, "a dependent style with a bundled parent is written")

        // A new key must not move the closing line past line 50.
        let long = "---\n" + String(repeating: "x: 1\n", count: 48) + "---\nBody.\n"
        controller.editor.setText(long)
        checkRefusal(check, controller, title: "The frontmatter could not be changed.", reason: "A new key would move the closing --- past line 50.") {
            controller.addBibliography(folder.appendingPathComponent("refs.bib"))
        }

        // A window with no editor has no target for the menu.
        let compare = controller.compare(withText: "Other.\n", title: "Other")
        defer { compare.close() }
        if let window = compare.window {
            for action in [
                #selector(EditorWindowController.chooseBibliography(_:)),
                #selector(EditorWindowController.chooseBundledStyle(_:)),
                #selector(EditorWindowController.chooseStyleFile(_:)),
                #selector(EditorWindowController.chooseLanguage(_:)),
                #selector(EditorWindowController.toggleReferences(_:)),
            ] {
                check(!handles(window, action), "a window with no editor has no \(action)")
            }
        }
    }

    private static func clickColumnTab(_ controller: EditorWindowController, _ index: Int) {
        (controller.columnTabsForTesting?.subviews[index] as? NSButton)?.performClick(nil)
    }

    /// The selected part of the control has the raised ground, and the window
    /// shows it: a sibling that paints over the control fails this.
    private static func controlIsPainted(_ controller: EditorWindowController) -> Bool {
        guard let tabs = controller.columnTabsForTesting,
              let frame = controller.window?.contentView?.superview else { return false }
        controller.layoutNowForTesting()
        let inner = tabs.convert(NSPoint(x: tabs.bounds.width * (tabs.selectedIndex == 0 ? 0.08 : 0.92), y: tabs.bounds.midY), to: frame)
        let outer = tabs.convert(NSPoint(x: -20, y: tabs.bounds.midY), to: frame)
        guard let lit = pixel(frame, at: inner), let ground = pixel(frame, at: outer) else { return false }
        let difference = abs(lit.redComponent - ground.redComponent)
            + abs(lit.greenComponent - ground.greenComponent)
            + abs(lit.blueComponent - ground.blueComponent)
        return difference > 0.01
    }

    private static func checkReferencesColumn(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = """
        ---
        bibliography: refs.bib
        ---
        A claim [@silva2020] and a lost key [@nobody].

        """
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        let editor = controller.editor
        let view = controller.referencesViewForTesting
        check(pump(timeout: 15) { controller.citations.report(for: text) != nil }, "the column has a report")
        check(!controller.isLibraryShownForTesting, "a window starts with no library")
        controller.layoutNowForTesting()
        let edges = controller.editorEdgesForTesting
        check(edges.pane == 0 && edges.page == 0, "the hidden column does not push the editor: \(edges)")
        check(controller.columnTabsForTesting == nil, "Write has no control")

        let show = referencesMenu().flatMap { item($0, "Show References") }
        func isOn() -> Bool {
            guard let show else { return false }
            return controller.validateMenuItem(show) && show.state == .on
        }

        // Keys with no request: the control shows, and the preview stays.
        controller.setViewMode(.split)
        check(controller.columnTabsForTesting?.selectedIndex == 0, "keys give the control in Split, on Preview")
        let tabsShown = pump(timeout: 1) {
            controller.layoutNowForTesting()
            return (controller.columnTabsForTesting?.frame.width ?? 0) > 100
        }
        check(tabsShown, "the control has its width: \(controller.columnTabsForTesting?.frame.width ?? 0)")
        check(controlIsPainted(controller), "the control is on the screen with the preview")
        check(controller.isPreviewVisible && !controller.isLibraryShownForTesting, "the control starts on the preview")
        check(!isOn(), "Show References has no mark on the preview")

        // The control goes when the keys go, and it comes back with them.
        clickColumnTab(controller, 1)
        check(controller.isLibraryShownForTesting && !controller.isPreviewVisible, "a click on References shows the library")
        check(isOn(), "Show References follows the control")
        editor.replace(range: NSRange(location: 0, length: (editor.source as NSString).length), with: "No keys.\n")
        check(pump(timeout: 15) { controller.columnTabsForTesting == nil }, "the control goes with the keys")
        check(controller.isPreviewVisible && !controller.isLibraryShownForTesting, "the preview comes back with no keys")
        editor.replace(range: NSRange(location: 0, length: (editor.source as NSString).length), with: text)
        check(pump(timeout: 15) { controller.columnTabsForTesting != nil }, "the control comes back with the keys")
        check(controller.isLibraryShownForTesting, "the tab stays")
        check(pump(timeout: 15) { controller.citations.report(for: editor.source) != nil }, "the report comes back")
        clickColumnTab(controller, 0)
        check(controller.isPreviewVisible && !controller.isLibraryShownForTesting, "a click on Preview is the way back")
        check(pump(timeout: 5) { controller.previewText.contains("(Silva 2020)") }, "the preview shows the text after the library")
        controller.setViewMode(.write)

        // Write goes to Split with the library.
        check(!isOn(), "Show References has no mark in Write")
        controller.toggleReferences(nil)
        check(controller.viewMode == .split, "the command goes to Split from Write")
        check(controller.isLibraryShownForTesting, "the column shows the library")
        check(!controller.isPreviewVisible, "the library takes the place of the preview")
        check(controller.isEditorVisible, "the editor stays in Split")
        check(isOn(), "Show References has the mark")
        check(controller.columnTabsForTesting?.selectedIndex == 1, "the control shows the state")
        check(controlIsPainted(controller), "the control is on the screen with the library")
        check(controller.window?.firstResponder === view.filterField.currentEditor(), "the filter field takes the focus")
        func balanced() -> Bool {
            controller.layoutNowForTesting()
            let widths = controller.columnWidthsForTesting
            return abs(widths.editor - widths.right) < 3
        }
        check(pump(timeout: 1) { balanced() && view.filterField.frame.width > 200 }, "the library keeps the divider, and the field fills its column: \(controller.columnWidthsForTesting), \(view.filterField.frame.width)")

        // A wide window: the rows stop at their measure, and the divider
        // stays. A measure that is too strong moves the divider.
        let narrow = controller.window?.frame.size
        controller.window?.setContentSize(NSSize(width: 1800, height: 800))
        check(pump(timeout: 1) { balanced() && view.filterField.frame.width == 720 }, "the rows keep their measure in a wide window: \(view.filterField.frame.width)")
        if let narrow { controller.window?.setFrame(NSRect(origin: controller.window?.frame.origin ?? .zero, size: narrow), display: false) }

        // Rows: a cited key with no entry goes first.
        check(view.rowsForTesting.map(\.key) == ["nobody", "silva2020"], "a missing key goes first: \(view.rowsForTesting.map(\.key))")
        check(view.rowsForTesting.first?.isMissing == true, "the first row is the missing key")
        check(view.rowsForTesting.last?.isCited == true, "the entry is marked as cited")
        check(view.rowsForTesting.last?.byline == "Silva, 2020", "the row has the authors and the year")

        // The filter ignores accents.
        view.filterForTesting("LUNG")
        check(view.rowsForTesting.map(\.key) == ["silva2020"], "the filter finds a word of the title")
        view.filterForTesting("nothing here")
        check(view.messageForTesting == "No entry matches.", "no match gives a message")
        view.filterForTesting("")

        // VoiceOver reads these labels through the accessibility API.
        check(view.filterField.accessibilityLabel() == "Filter the library", "the field has its label")
        let table = view.tableForTesting
        check(table.accessibilityLabel() == "Library", "the table has its label")
        check(table.accessibilityRole() == .table, "the table has its role")
        let cell = view.cellForTesting(row: 1)
        check(cell?.isAccessibilityElement() == true, "a row is one element")
        check(
            cell?.accessibilityLabel() == "silva2020, cited, Silva, 2020, Lung function at home",
            "a row reads as a sentence: \(cell?.accessibilityLabel() ?? "nil")"
        )
        check(view.cellForTesting(row: 0)?.accessibilityLabel() == "nobody, cited, no entry", "a missing key reads as a fault")
        check(controller.columnTabsForTesting?.accessibilityLabel() == "Right column", "the control has its label")
        check(controller.columnTabsForTesting?.accessibilityRole() == .radioGroup, "the control has its role")
        check(
            controller.columnTabsForTesting?.subviews.map { $0.accessibilityLabel() ?? "" } == ["Preview", "References"],
            "the parts of the control have their labels"
        )

        // The theme.
        let palette = ThemeManager.shared.resolved()
        if let palette {
            check(view.tableBackgroundForTesting == palette.colors.background, "the table has the reading ground")
        }

        // The command switches back, and the control stays as the way forward.
        controller.toggleReferences(nil)
        check(!controller.isLibraryShownForTesting, "the toggle takes the library away")
        check(controller.isPreviewVisible, "the preview comes back")
        check(controller.columnTabsForTesting?.selectedIndex == 0, "the control follows the toggle")
        check(controller.window?.firstResponder === editor.textView, "the editor takes the focus back")

        // Escape in the preview goes to the editor.
        let preview = controller.previewTextViewForTesting
        controller.window?.makeFirstResponder(preview)
        if let event = keyDown(53) { preview.keyDown(with: event) }
        check(controller.window?.firstResponder === editor.textView, "Escape in the preview gives the focus to the editor")

        // Preview always shows the preview, with the tab on References too.
        controller.toggleReferences(nil)
        controller.setViewMode(.preview)
        check(controller.isPreviewVisible && !controller.isLibraryShownForTesting, "Preview shows the preview with the tab on References")
        check(controller.columnTabsForTesting == nil, "Preview has no control")
        check(!isOn(), "Show References has no mark in Preview")
        controller.setViewMode(.split)
        check(controller.isLibraryShownForTesting, "the tab stays with the window")
        controller.toggleReferences(nil)
        controller.setViewMode(.preview)
        controller.toggleReferences(nil)
        check(controller.viewMode == .split, "the command goes to Split from Preview")
        check(controller.isLibraryShownForTesting, "the command from Preview shows the library")
        controller.setViewMode(.write)
        check(!controller.isLibraryShownForTesting, "Write has no library")
        controller.setViewMode(.split)
        check(controller.isLibraryShownForTesting, "the request stays with the window")

        // Another window keeps its own state, and no request shows no change.
        let (other, otherController) = try citationDocument(text: "Plain.\n", folder: folder.appendingPathComponent("other"))
        defer { closeCitationDocument(other) }
        otherController.setViewMode(.split)
        check(
            !otherController.isLibraryShownForTesting && otherController.isPreviewVisible && otherController.columnTabsForTesting == nil,
            "a window with no keys and no request shows no change"
        )
        otherController.toggleReferences(nil)
        let empty = otherController.referencesViewForTesting.messageForTesting ?? ""
        check(empty.hasPrefix("No references yet."), "a request with no library says what to do: \(empty)")
        check(otherController.isLibraryShownForTesting && controller.isLibraryShownForTesting, "each window has its own state")
        otherController.toggleReferences(nil)
        check(otherController.columnTabsForTesting != nil, "after a request the control stays, with no keys")
        check(controller.isLibraryShownForTesting, "the other window keeps its state")

        // A file that is missing: a message, and the key under it.
        let lost = "---\nbibliography: lost.bib\n---\nA claim [@nobody].\n"
        let (missing, missingController) = try citationDocument(text: lost, folder: folder.appendingPathComponent("lost"))
        defer { closeCitationDocument(missing) }
        missingController.toggleReferences(nil)
        let lostView = missingController.referencesViewForTesting
        check(pump(timeout: 15) { lostView.rowsForTesting.map(\.key) == ["nobody"] }, "a missing key shows with no library")
        lostView.layoutSubtreeIfNeeded()
        check(lostView.messageForTesting?.hasPrefix("No references yet.") == true, "the message stands with the missing key")
        check(lostView.messageClearsRowsForTesting, "the message does not cover the rows")

        // Projector mode: bigger text, the same rows, the same minimum width.
        let height = view.rowHeightForTesting
        controller.toggleProjectorMode(nil)
        check(view.rowHeightForTesting > height, "projector mode gives taller rows")
        check(view.rowsForTesting.map(\.key) == ["nobody", "silva2020"], "projector mode keeps the rows")
        check(controller.window?.minSize.width == 640, "the minimum width stays")
        controller.window?.setContentSize(NSSize(width: 640, height: 400))
        controller.layoutNowForTesting()
        view.layoutSubtreeIfNeeded()
        check(view.tableForTesting.bounds.width > 100, "the table has room at the minimum width")
        check(pump(timeout: 1) { balanced() }, "the divider stays at the minimum width: \(controller.columnWidthsForTesting)")
        controller.toggleProjectorMode(nil)
        check(view.rowHeightForTesting == height, "the rows come back after projector mode")
        controller.toggleReferences(nil)
    }

    private static func keyDown(_ keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: keyCode == 53 ? "\u{1B}" : "\r",
            charactersIgnoringModifiers: keyCode == 53 ? "\u{1B}" : "\r",
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private static func checkReferenceInsertion(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = "---\nbibliography: refs.bib\n---\nFirst line.\n"
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        let editor = controller.editor
        let textView = editor.textView
        let undo = textView.undoManager
        let view = controller.referencesViewForTesting
        check(pump(timeout: 15) { !(controller.citations.report(for: text)?.library.isEmpty ?? true) }, "the library is ready")
        controller.toggleReferences(nil)
        check(view.rowsForTesting.map(\.key) == ["silva2020"], "the table has the entry")

        // Return in the table.
        let end = (text as NSString).length - 1
        textView.setSelectedRange(NSRange(location: end, length: 0))
        view.selectForTesting(key: "silva2020")
        let table = view.tableForTesting
        controller.window?.makeFirstResponder(table)
        let before = editor.revision
        if let event = keyDown(36) { table.keyDown(with: event) }
        let inserted = "---\nbibliography: refs.bib\n---\nFirst line.[@silva2020]\n"
        check(pump(timeout: 5) { editor.source == inserted }, "Return inserts the citation: \(editor.source)")
        check(editor.revision == before + 1, "the insertion is one edit")
        check(textView.selectedRange() == NSRange(location: end + 12, length: 0), "the caret goes after the citation")
        check(controller.window?.firstResponder === textView, "the focus goes back to the editor")
        undo?.undo()
        check(editor.source == text, "one Undo takes the citation back")
        undo?.redo()
        check(editor.source == inserted, "Redo puts it back")

        // A double click goes the same way. The caret in a citation joins it.
        let inside = (inserted as NSString).range(of: "@silva").location + 2
        textView.setSelectedRange(NSRange(location: inside, length: 0))
        view.filterForTesting("silva")
        table.sendAction(table.doubleAction, to: table.target)
        _ = pump(timeout: 0.3) { false }
        check(editor.source == inserted, "a double click off the rows does nothing")
        controller.window?.makeFirstResponder(view.filterField)
        if let field = view.filterField.currentEditor() as? NSTextView {
            field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }
        check(pump(timeout: 5) { editor.source.contains("[@silva2020; @silva2020]") }, "Return in the field takes the first entry, and joins the citation: \(editor.source)")
        check(controller.window?.firstResponder === textView, "the focus goes back from the field")
        view.filterForTesting("")

        // Escape in the field clears the filter, then leaves.
        view.filterForTesting("silva")
        controller.window?.makeFirstResponder(view.filterField)
        (view.filterField.currentEditor() as? NSTextView)?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        check(view.filterField.stringValue.isEmpty, "Escape clears the filter")
        (view.filterField.currentEditor() as? NSTextView)?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        check(controller.window?.firstResponder === textView, "a second Escape gives the focus to the editor")

        // Text in the frontmatter stops it from being one, so the rule moves it.
        undo?.undo()
        undo?.undo()
        check(editor.source == text, "two Undos restore the text")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        view.selectForTesting(key: "silva2020")
        if let event = keyDown(36) { table.keyDown(with: event) }
        check(pump(timeout: 5) { editor.source.hasPrefix("---\nbibliography: refs.bib\n---\n[@silva2020]\n\nFirst line.") }, "a caret in the frontmatter inserts after it: \(editor.source)")

        // Escape leaves the table.
        controller.window?.makeFirstResponder(table)
        if let event = keyDown(53) { table.keyDown(with: event) }
        check(controller.window?.firstResponder === textView, "Escape gives the focus to the editor")

        // Return with no filter and no selection has nothing to insert.
        let before2 = editor.source
        view.filterForTesting("")
        view.selectForTesting(key: nil)
        controller.window?.makeFirstResponder(view.filterField)
        (view.filterField.currentEditor() as? NSTextView)?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        if let event = keyDown(36) { table.keyDown(with: event) }
        _ = pump(timeout: 0.3) { false }
        check(editor.source == before2, "Return with no filter and no selection inserts nothing")

        // A failed answer for the menu gives a status.
        controller.citations.useEngineForTesting(try FailingCitationEngine())
        controller.refreshReferenceChoices {}
        check(
            pump(timeout: 5) { controller.overlayTextForTesting == "The References menu cannot show the current choices." },
            "a failed answer for the menu gives a status"
        )
    }

    /// Runs the real list. `complete` does not return while the list is open,
    /// so a block on the main queue gives the list its key.
    private static func checkCompletionList(_ check: (Bool, String) -> Void, folder: URL) throws {
        let text = """
        ---
        bibliography: refs.bib
        ---
        - A claim

        `code `

        """
        let (document, controller) = try citationDocument(text: text, folder: folder)
        defer { closeCitationDocument(document) }
        let editor = controller.editor
        let textView = editor.textView
        guard let window = controller.window else { return }
        check(spin(timeout: 15) { !editor.citationKeys.isEmpty }, "the library is ready")

        window.makeFirstResponder(textView)

        /// `pump`, and each event goes out too: an event left in the queue
        /// closes the list.
        func spin(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, !condition() {
                if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
            }
            return condition()
        }
        _ = spin(timeout: 0.3) { false }

        func enter(_ text: String) {
            textView.asTyping {
                for character in text {
                    textView.insertText(String(character), replacementRange: textView.selectedRange())
                }
            }
        }
        func listIsOpen() -> Bool {
            NSApp.windows.contains { "\(type(of: $0))".contains("Completion") && $0.isVisible }
        }
        /// The count of the lists that took a key.
        var answered = 0
        func answer(_ characters: String, keyCode: UInt16, attempts: Int = 300) {
            guard attempts > 0 else { return }
            guard listIsOpen() else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    answer(characters, keyCode: keyCode, attempts: attempts - 1)
                }
                return
            }
            answered += 1
            post(characters, keyCode: keyCode, to: window)
        }

        let lineEnd = (text as NSString).range(of: "- A claim").upperBound
        textView.setSelectedRange(NSRange(location: lineEnd, length: 0))
        let queries = editor.citationMatchRuns
        enter(" [@")
        let beforeKey = editor.source
        // This block is one run loop turn, so the undo group of the turn must
        // end by hand, as it does at the end of a key press.
        textView.undoManager?.endUndoGrouping()
        textView.undoManager?.beginUndoGrouping()
        let generation = editor.editGeneration
        answer("\r", keyCode: 36)
        check(spin(timeout: 5) { answered == 1 && !listIsOpen() }, "a typed sign opens the list, and Return closes it")
        check(editor.source.contains("- A claim [@silva2020\n"), "Return inserts the key with its sign")
        check(editor.citationMatchRuns == queries + 1, "one list makes one query")
        check(editor.editGeneration == generation + 1, "browsing makes no edit, and the key is one edit")

        textView.undoManager?.undo()
        check(editor.source == beforeKey, "one Undo removes the key and keeps the sign")
        textView.undoManager?.redo()
        check(editor.source.contains("[@silva2020\n"), "Redo puts the key back")
        _ = spin(timeout: 0.4) { false }
        check(!listIsOpen(), "Redo does not open the list")

        enter("]")
        check(editor.handleNewline(), "list continuation works after a citation")
        check(editor.source.contains("[@silva2020]\n- "), "the next item starts")

        // Escape closes the list, and a letter does not open it again.
        enter("[@")
        answer("\u{1B}", keyCode: 53)
        check(spin(timeout: 5) { answered == 2 && !listIsOpen() }, "the sign opens the list, and Escape closes it")
        check(editor.source.contains("- [@\n"), "Escape leaves the sign")
        enter("s")
        _ = spin(timeout: 0.5) { false }
        check(answered == 2 && !listIsOpen(), "the list stays shut after Escape")

        // A typed letter closes the list, and the list opens again for the query.
        enter("; @")
        answer("l", keyCode: 37)
        check(spin(timeout: 5) { answered == 3 && editor.source.contains("; @l") }, "a letter closes the list and goes in the text")
        answer("\t", keyCode: 48)
        check(spin(timeout: 5) { answered == 4 && !listIsOpen() }, "the list opens again for the query, and Tab closes it")
        check(editor.source.contains("; @silva2020"), "Tab inserts the key")

        let code = (editor.source as NSString).range(of: "`code `")
        textView.setSelectedRange(NSRange(location: code.location + 6, length: 0))
        enter("@")
        _ = spin(timeout: 0.6) { false }
        check(answered == 4 && !listIsOpen(), "no list in inline code")

        textView.setSelectedRange(NSRange(location: (editor.source as NSString).length, length: 0))
        enter("\nana@")
        _ = spin(timeout: 0.6) { false }
        check(!listIsOpen(), "no list in an email address")

        enter(" \"")
        check(editor.source.hasSuffix("ana@ \u{201C}"), "smart typography works beside the sign")

        // A real key event, through `keyDown`, arms the list.
        enter("\n")
        if let key = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "@",
            charactersIgnoringModifiers: "@",
            isARepeat: false,
            keyCode: 19
        ) {
            textView.keyDown(with: key)
        }
        check(editor.source.hasSuffix("\n@"), "a key event reaches the text")
        check(editor.isCompletionArmed, "a key event arms the list")
        answer("\u{1B}", keyCode: 53)
        check(spin(timeout: 5) { answered == 5 && !listIsOpen() }, "the list from a key event opens and closes")
    }

    /// The list closes at once when `NSApp.run` is not running. `body` starts
    /// from the run loop, because a block on the main queue holds the later
    /// blocks while the list is open.
    private static func inRunningApp(_ body: () throws -> Void) throws {
        try withoutActuallyEscaping(body) { body in
            var failure: Error?
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    do {
                        try body()
                    } catch {
                        failure = error
                    }
                    NSApp.stop(nil)
                    // `run` looks at `stop` after the next event.
                    if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            NSApp.run()
            if let failure { throw failure }
        }
    }

    /// The list runs its own event loop, so a key goes to the event queue.
    private static func post(_ characters: String, keyCode: UInt16, to window: NSWindow) {
        for kind in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: kind,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
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

    /// Compares a pixel at the empty right end of the text column on the line
    /// of `sourceLocation` with the same column on the document's last line,
    /// which carries no decoration.
    private static func lineIsTinted(_ textView: EditorTextView, sourceLocation: Int) -> Bool {
        let length = (textView.string as NSString).length
        guard let line = textView.lineRects(for: NSRange(location: sourceLocation, length: 1)).first,
              let reference = textView.lineRects(for: NSRange(location: max(0, length - 1), length: 1)).last,
              let lit = pixel(textView, at: NSPoint(x: line.maxX - 10, y: line.midY)),
              let plain = pixel(textView, at: NSPoint(x: reference.maxX - 10, y: reference.midY)) else { return false }
        let difference = abs(lit.redComponent - plain.redComponent)
            + abs(lit.greenComponent - plain.greenComponent)
            + abs(lit.blueComponent - plain.blueComponent)
        return difference > 0.04
    }

    private static func pixel(_ view: NSView, at point: NSPoint) -> NSColor? {
        let sample = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: sample) else { return nil }
        view.cacheDisplay(in: sample, to: bitmap)
        return bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)
    }
}

/// The real engine, with a delay before each report, and a count of reports.
private final class SlowCitationEngine: CitationEngineProtocol, @unchecked Sendable {
    private let engine: CitationEngine
    private let delay: TimeInterval
    private let shareDelay: TimeInterval
    private let lock = NSLock()
    private var count = 0

    init(delay: TimeInterval, shareDelay: TimeInterval = 0) throws {
        guard let root = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        engine = try CitationEngine(resources: root.appendingPathComponent("Citations"))
        self.delay = delay
        self.shareDelay = shareDelay
    }

    var analyses: Int { lock.withLock { count } }

    func analyse(_ source: String) -> CitationReport {
        lock.withLock { count += 1 }
        Thread.sleep(forTimeInterval: delay)
        return engine.analyse(source)
    }

    func setSources(_ sources: CitationSources) { engine.setSources(sources) }
    func shareSource(_ source: String) throws -> String {
        Thread.sleep(forTimeInterval: shareDelay)
        return try engine.shareSource(source)
    }
    func shareStyleNote(_ shared: String) throws -> String? { try engine.shareStyleNote(shared) }
    func readMeta(_ source: String) throws -> CitationMeta { try engine.readMeta(source) }
    func bundledStyle(_ id: String) -> String? { engine.bundledStyle(id) }
    func bundledLocale(_ tag: String) -> String? { engine.bundledLocale(tag) }
    func resolveNative(_ request: CitationSourceRequest, known: CitationKnownFiles) throws -> CitationPlan {
        try engine.resolveNative(request, known: known)
    }
    func setMeta(_ source: String, key: String, value: String?) throws -> String {
        try engine.setMeta(source, key: key, value: value)
    }
    func addBibliography(_ source: String, path: String) throws -> String {
        try engine.addBibliography(source, path: path)
    }
    func referenceChoices(_ source: String) throws -> CitationChoices { try engine.referenceChoices(source) }
    func setChoice(_ source: String, key: String, value: String) throws -> String {
        try engine.setChoice(source, key: key, value: value)
    }
    func insertCitation(_ source: String, position: Int, key: String) throws -> CitationInsertion {
        try engine.insertCitation(source, position: position, key: key)
    }
    func fileChange(_ source: String, name: String, path: String) throws -> CitationMetaChange {
        try engine.fileChange(source, name: name, path: path)
    }
}

/// An engine whose reports all fail, as a broken script does.
private final class FailingCitationEngine: CitationEngineProtocol, @unchecked Sendable {
    private let engine: CitationEngine

    init() throws {
        guard let root = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        engine = try CitationEngine(resources: root.appendingPathComponent("Citations"))
    }

    func analyse(_ source: String) -> CitationReport {
        CitationReport(failure: "The citation code failed.", source: source)
    }

    func setSources(_ sources: CitationSources) {}
    func shareSource(_ source: String) throws -> String {
        throw CitationEngineError.script("The citation code failed.")
    }
    func shareStyleNote(_ shared: String) throws -> String? { nil }
    func readMeta(_ source: String) throws -> CitationMeta { try engine.readMeta(source) }
    func bundledStyle(_ id: String) -> String? { engine.bundledStyle(id) }
    func bundledLocale(_ tag: String) -> String? { engine.bundledLocale(tag) }
    func resolveNative(_ request: CitationSourceRequest, known: CitationKnownFiles) throws -> CitationPlan {
        try engine.resolveNative(request, known: known)
    }
    func setMeta(_ source: String, key: String, value: String?) throws -> String {
        try engine.setMeta(source, key: key, value: value)
    }
    func addBibliography(_ source: String, path: String) throws -> String {
        try engine.addBibliography(source, path: path)
    }
    func referenceChoices(_ source: String) throws -> CitationChoices {
        throw CitationEngineError.script("The citation code failed.")
    }
    func setChoice(_ source: String, key: String, value: String) throws -> String {
        try engine.setChoice(source, key: key, value: value)
    }
    func insertCitation(_ source: String, position: Int, key: String) throws -> CitationInsertion {
        try engine.insertCitation(source, position: position, key: key)
    }
    func fileChange(_ source: String, name: String, path: String) throws -> CitationMetaChange {
        try engine.fileChange(source, name: name, path: path)
    }
}
