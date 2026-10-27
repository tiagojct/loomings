import AppKit
import LoomingsDocuments
import LoomingsEditor

/// A native document with three possible homes: a user file, a local shelf
/// file, or nothing (untitled). Shelf documents are ordinary file documents
/// whose file lives in Application Support, so they inherit NSDocument's
/// autosave, versions, recents and external-change handling.
@objc(LoomingsDocument)
final class LoomingsDocument: NSDocument {
    weak var editor: EditorController?
    var pendingText = ""

    private(set) var textFile = TextFile(text: "")
    private(set) var saveGeneration = SaveGeneration()
    private(set) var lastWrittenGeneration: UInt64 = 0
    private(set) var lastKnownStamp: FileStamp?
    private(set) var shelfEntry: ShelfEntry?

    var shelf = LocalShelf.shared
    var notesRecentDocuments = true
    private var isSaving = false
    private var isCheckingExternalChange = false

    override init() {
        super.init()
        fileType = "net.daringfireball.markdown"
    }

    override class var autosavesInPlace: Bool { true }
    override class var preservesVersions: Bool { true }

    /// `read(from:)` and `data(ofType:)` use `MainActor.assumeIsolated`, which
    /// traps off the main thread. Say so, rather than rely on the default.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override var displayName: String! {
        get { shelfEntry?.title ?? super.displayName }
        set { super.displayName = newValue }
    }

    var isContentEdited: Bool {
        saveGeneration.isEdited(currentGeneration: editor?.editGeneration ?? 0)
    }

    // MARK: - Windows

    override func makeWindowControllers() {
        if lastKnownStamp == nil, let fileURL {
            lastKnownStamp = FileStamp(url: fileURL)
        }
        applyShelfMetadata()
        let controller = EditorWindowController(document: self)
        addWindowController(controller)
        applyShelfMetadata()
        applyTitle()
    }

    // MARK: - Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        let file = try TextFileCodec.decode(data)
        textFile = file
        pendingText = file.text
        saveGeneration = SaveGeneration()
        lastWrittenGeneration = 0
        if let fileURL {
            lastKnownStamp = FileStamp(url: fileURL)
        }

        MainActor.assumeIsolated {
            applyShelfMetadata()
            applyTitle()
            editor?.setText(file.text)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = MainActor.assumeIsolated { editor?.source ?? pendingText }
        let generation = MainActor.assumeIsolated { editor?.editGeneration ?? 0 }
        lastWrittenGeneration = generation

        return try TextFileCodec.encode(
            TextFile(
                text: text,
                encoding: textFile.encoding,
                hasBOM: textFile.hasBOM,
                lineEnding: textFile.lineEnding
            )
        )
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        isSaving = true
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            if error == nil {
                self.finishSave(at: url, operation: saveOperation)
            }
            self.isSaving = false
            completionHandler(error)
        }
    }

    /// Force the write onto the main thread: the editor's text is main-actor
    /// state and Stage 2 does not snapshot it for a background write yet.
    override func canAsynchronouslyWrite(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType
    ) -> Bool {
        false
    }

    private func finishSave(at url: URL, operation: NSDocument.SaveOperationType) {
        // NSSaveOperation = 0, NSSaveAsOperation = 1,
        // NSAutosaveInPlaceOperation = 4. The imported enum exposes no
        // named cases through this toolchain, so compare raw values.
        let homeSave = operation.rawValue == 0 || operation.rawValue == 1 || operation.rawValue == 4
        guard homeSave else { return }

        saveGeneration.recordSave(snapshot: lastWrittenGeneration)
        lastKnownStamp = FileStamp(url: url)
        if let entry = shelf.entry(containing: url) {
            shelfEntry = entry
            try? shelf.touch(id: entry.id, at: Date())
            applyTitle()
        }
    }

    // MARK: - Shelf

    /// Save to Shelf is for untitled documents and for documents already on
    /// the shelf. A document that has its own file stays attached to it:
    /// moving it onto the shelf would silently stop writing to that file.
    var canSaveToShelf: Bool {
        guard let url = fileURL else { return true }
        return shelf.contains(url)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(saveToShelf(_:)) { return canSaveToShelf }
        return super.validateUserInterfaceItem(item)
    }

    @objc func saveToShelf(_ sender: Any?) {
        guard canSaveToShelf else { return }
        if let url = fileURL, shelf.contains(url) {
            save(sender)
            return
        }

        do {
            let data = try data(ofType: fileType ?? "net.daringfireball.markdown")
            let generation = lastWrittenGeneration
            let entry = try shelf.create(
                title: suggestedShelfTitle(),
                data: data,
                fileExtension: "md"
            )

            shelfEntry = entry
            fileURL = shelf.contentURL(for: entry)
            fileType = "net.daringfireball.markdown"
            fileModificationDate = Date()
            displayName = entry.title
            lastKnownStamp = FileStamp(url: shelf.contentURL(for: entry))
            saveGeneration.recordSave(snapshot: generation)
            updateChangeCount(.changeCleared)
            if notesRecentDocuments {
                NSDocumentController.shared.noteNewRecentDocumentURL(shelf.contentURL(for: entry))
            }
            applyTitle()
        } catch {
            presentError(error)
        }
    }

    override func rename(_ sender: Any?) {
        guard let entry = shelfEntry ?? fileURL.flatMap({ shelf.entry(containing: $0) }) else {
            super.rename(sender)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename Document"
        alert.informativeText = "Only the title changes. The shelf keeps its stable identifier."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = entry.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try shelf.updateTitle(id: entry.id, title: field.stringValue)
            shelfEntry = try shelf.entry(id: entry.id)
            if let title = shelfEntry?.title {
                displayName = title
            }
            applyTitle()
        } catch {
            presentError(error)
        }
    }

    private func applyShelfMetadata() {
        guard let url = fileURL, let entry = shelf.entry(containing: url) else {
            shelfEntry = nil
            return
        }
        shelfEntry = entry
        displayName = entry.title
    }

    private func applyTitle() {
        guard let title = shelfEntry?.title ?? displayName else { return }
        for controller in windowControllers {
            controller.window?.title = title
        }
    }

    private func suggestedShelfTitle() -> String {
        if let name = displayName,
           !name.isEmpty,
           !name.hasPrefix("Untitled") {
            return name
        }
        let firstLine = pendingTextOrEditorText()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        var title = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = title.first, "#>-* \t".contains(first) {
            title.removeFirst()
        }
        return title.isEmpty ? "Untitled" : String(title.prefix(80))
    }

    private func pendingTextOrEditorText() -> String {
        MainActor.assumeIsolated { editor?.source ?? pendingText }
    }

    // MARK: - External changes

    @objc func checkForExternalChange() {
        guard !isSaving,
              !isCheckingExternalChange,
              let url = fileURL,
              let previous = lastKnownStamp else {
            return
        }

        let change = FileChangeDetector.change(previous: previous, at: url)
        guard change != .none else { return }

        if change == .deleted {
            presentDeletedAlert(for: url)
            return
        }

        if !isDocumentEdited {
            reloadFromDisk(url)
            return
        }

        isCheckingExternalChange = true
        let alert = NSAlert()
        alert.messageText = "The file changed on disk"
        alert.informativeText = "You have edits in this window. Reloading replaces them with the version on disk."
        alert.addButton(withTitle: "Keep My Version")
        alert.addButton(withTitle: "Reload from Disk")

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isCheckingExternalChange = false
            if response == .alertSecondButtonReturn {
                self.reloadFromDisk(url)
            } else {
                self.lastKnownStamp = FileStamp(url: url)
            }
        }

        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func presentDeletedAlert(for url: URL) {
        isCheckingExternalChange = true
        let alert = NSAlert()
        alert.messageText = "The file was deleted"
        alert.informativeText = "The document is still open in memory. Keep it and save it elsewhere, or close it."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Close Document")

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isCheckingExternalChange = false
            if response == .alertSecondButtonReturn {
                self.close()
            } else {
                self.lastKnownStamp = FileStamp(exists: false, modificationDate: nil, size: nil)
            }
        }

        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func reloadFromDisk(_ url: URL) {
        do {
            try revert(
                toContentsOf: url,
                ofType: fileType ?? "net.daringfireball.markdown"
            )
            lastKnownStamp = FileStamp(url: url)
            saveGeneration = SaveGeneration()
            lastWrittenGeneration = 0
            updateChangeCount(.changeCleared)
        } catch {
            presentError(error)
        }
    }
}
