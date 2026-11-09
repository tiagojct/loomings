import AppKit
import LoomingsCitations
import LoomingsDocuments
import LoomingsDocx
import LoomingsEditor
import LoomingsMarkdown
import LoomingsPreview
import LoomingsShare
import LoomingsTeaching
import LoomingsTheme
import UniformTypeIdentifiers

@MainActor
final class EditorWindowController: NSWindowController,
    NSToolbarDelegate,
    NSWindowDelegate,
    NSSplitViewDelegate,
    NSMenuItemValidation
{
    let editor = EditorController()
    let citations = CitationController()
    weak var loomingsDocument: LoomingsDocument?

    enum ViewMode: Int {
        case write
        case split
        case preview
    }

    private let containerView = NSView()
    private let scrollView = DocumentScrollView()
    private let previewScrollView = NSScrollView()
    private let previewTextView = PreviewTextView()
    /// The right pane of Split, and the page of Preview. In Split it can hold
    /// the library in the place of the preview, under `columnTabs`.
    private let rightColumn = RightColumnView()
    private let columnTabs = ModeSwitch(labels: ["Preview", "References"], name: "Right column")
    private let referencesView = ReferencesView()
    /// The room above the preview and the library.
    private var columnTop: NSLayoutConstraint!
    private let splitView = ThemedSplitView()
    /// The file sidebar: a card that floats over the editor's left edge. It
    /// takes no room from the editor. Hidden unless the feature is on and the
    /// window shows it.
    private let sidebar = SidebarView()
    private var sidebarOn = false
    /// A window of its own folder. Nil until the writer chooses one here.
    private var sidebarFolderOverride: URL?
    private var sidebarShown = EditorPreferences.sidebarVisible
    private var featuresObserver: NSObjectProtocol?
    private let statusBar = StatusBarView()
    private var statusHeightConstraint: NSLayoutConstraint!
    private var lineRuler: LineNumberRulerView!
    private var statusWorkItem: DispatchWorkItem?
    private var previewWorkItem: DispatchWorkItem?
    private(set) var viewMode: ViewMode = .write
    private var syncSource: String?
    private var syncUntil = Date.distantPast
    private var previewGeneration = 0
    /// The newest generation, readable from the preview queue: a render that
    /// waited behind a newer one never starts.
    private let previewTicket = PreviewTicket()
    private let previewPipeline = PreviewPipeline()
    /// Links the text in the preview to the editor's text, when they differ.
    private var citationLines: CitationLineMap?
    private let previewQueue = DispatchQueue(
        label: "eu.tiagojacinto.loomings.preview",
        qos: .userInitiated
    )

    init(document: LoomingsDocument) {
        self.loomingsDocument = document

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The title, the centred mode switch and three tools fit from 640 pt.
        window.minSize = NSSize(width: 640, height: 360)
        // The tab setting of System Settings decides; the tab bar's + asks the
        // app for a new window (`newWindowForTab`).
        window.tabbingMode = .automatic
        // An unsaved document and the window's place come back after a restart.
        window.isRestorable = true
        window.center()

        super.init(window: window)

        window.title = document.displayName
        window.windowController = self
        window.delegate = self

        configureContent()
        installOverlay()
        history.load(fileURL: document.fileURL)
        history.onError = { [weak self] reason in
            guard let self, let window = self.window else { return }
            let alert = NSAlert()
            alert.messageText = "The writing history could not be saved."
            alert.informativeText = "\(reason)\n\nThe document itself is not affected. Loomings keeps trying; free some disk space or check the Application Support folder."
            alert.beginSheetModal(for: window)
        }
        configureToolbar()
        wireEditorCallbacks()

        scrollView.onOpenFiles = { urls in
            for url in urls {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, error in
                    if let error {
                        NSApp.presentError(error)
                    }
                }
            }
        }

        scrollView.onInsertImages = { [weak self] urls, point in
            guard let self else { return }
            let textView = self.editor.textView
            let location = textView.characterIndexForInsertion(at: textView.convert(point, from: nil))
            self.editor.insertImages(
                urls,
                at: location,
                relativeTo: self.loomingsDocument?.imageLinkDirectory
            )
            self.window?.makeFirstResponder(textView)
        }

        sidebar.onOpen = { [weak self] url in self?.openFromSidebar(url) }
        sidebar.onChooseFolder = { [weak self] in self?.chooseSidebarFolder() }
        sidebar.onNavigate = { [weak self] url in self?.setSidebarFolder(url) }
        sidebar.onEscape = { [weak self] in
            guard let self, self.sidebarShown else { return }
            self.toggleSidebar(nil)
            self.window?.makeFirstResponder(self.editor.textView)
        }
        featuresObserver = NotificationCenter.default.addObserver(
            forName: .loomingsFeaturesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.featuresChanged() }
        }

        document.editor = editor
        editor.setText(document.pendingText)
        applyPreferences()
        applyViewMode()
        applySidebar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Loomings windows are created in code")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        applyColumnWidth()
        editor.requestVisibleStyling()
        lineRuler.needsDisplay = true
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let title = loomingsDocument?.displayName {
            window?.title = title
        }
        ensureWindowOnScreen()
        applyColumnWidth()
        editor.requestVisibleStyling()
        updateStatus()
        lineRuler.needsDisplay = true
    }

    private func ensureWindowOnScreen() {
        guard let window else { return }
        let screens = NSScreen.screens
        if screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            return
        }
        window.center()
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            var frame = window.frame
            frame.origin.x = min(
                max(frame.origin.x, visible.minX),
                visible.maxX - frame.width
            )
            frame.origin.y = min(
                max(frame.origin.y, visible.minY),
                visible.maxY - frame.height
            )
            window.setFrame(frame, display: false)
        }
    }

    func windowDidResize(_ notification: Notification) {
        applyColumnWidth()
        layoutPreview()
        lineRuler.needsDisplay = true
    }

    private func configureContent() {
        guard let window else { return }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.verticalScroller = ThemedScroller()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = editor.textView
        textView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: 900, height: 700)
        )
        textView.minSize = NSSize(width: 0, height: 0)
        scrollView.documentView = textView
        editor.observeScrolling(in: scrollView)

        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.verticalScroller = ThemedScroller()
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = false
        previewScrollView.autohidesScrollers = true
        previewScrollView.borderType = .noBorder
        previewScrollView.drawsBackground = true
        previewScrollView.backgroundColor = .textBackgroundColor
        previewTextView.frame = NSRect(x: 0, y: 0, width: 480, height: 700)
        previewTextView.minSize = NSSize(width: 0, height: 0)
        previewScrollView.documentView = previewTextView
        previewTextView.observeScrolling(in: previewScrollView)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        referencesView.translatesAutoresizingMaskIntoConstraints = false
        columnTabs.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.addSubview(columnTabs)
        let columnContent = NSLayoutGuide()
        rightColumn.addLayoutGuide(columnContent)
        columnTop = columnContent.topAnchor.constraint(equalTo: rightColumn.topAnchor)
        NSLayoutConstraint.activate([
            columnTabs.topAnchor.constraint(equalTo: rightColumn.topAnchor, constant: Self.columnTabsInset),
            columnTabs.centerXAnchor.constraint(equalTo: rightColumn.centerXAnchor),
            columnTop,
            columnContent.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor),
            columnContent.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            columnContent.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
        ])
        for view in [previewScrollView, referencesView] as [NSView] {
            rightColumn.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: columnContent.topAnchor),
                view.bottomAnchor.constraint(equalTo: columnContent.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: columnContent.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: columnContent.trailingAnchor),
            ])
        }

        // A window starts in Write. With the column in the first layout, the
        // split view can give it all the width, and the editor scrolls sideways.
        rightColumn.isHidden = true
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(rightColumn)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        // Hidden before the first layout, as the right column is.
        containerView.addSubview(splitView)
        containerView.addSubview(statusBar)

        statusHeightConstraint = statusBar.heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: containerView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: splitView.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            statusHeightConstraint,
        ])

        // The floating sidebar sits above the split view.
        sidebar.isHidden = true
        sidebar.alphaValue = 0
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: SidebarView.margin),
            sidebar.topAnchor.constraint(equalTo: containerView.topAnchor, constant: SidebarView.margin),
            sidebar.bottomAnchor.constraint(lessThanOrEqualTo: statusBar.topAnchor, constant: -SidebarView.margin),
            sidebar.widthAnchor.constraint(equalToConstant: SidebarView.width),
        ])

        window.contentView = containerView

        scrollView.hasVerticalRuler = true
        lineRuler = LineNumberRulerView(scrollView: scrollView, editor: editor)
        scrollView.verticalRulerView = lineRuler
        scrollView.rulersVisible = effectiveShowLineNumbers
    }

    private func wireEditorCallbacks() {
        editor.onEdit = { [weak self] in
            guard let self else { return }
            // Notes rest while the writer types and come back with the parse.
            self.editor.textView.setDecorations([], for: "notes")
            self.schedulePreviewUpdate()
            self.hideSidebarForWriting()
        }
        editor.onTextClick = { [weak self] in self?.hideSidebarForWriting() }
        editor.onAnalysis = { [weak self] _ in
            guard let self else { return }
            self.applyTeachingReport()
            if self.editor.lastAppliedRevision == self.editor.revision, self.editor.revision > 0 {
                // The text is copied only for a document that records.
                if self.history.isRecording { self.history.textChanged(self.editor.source) }
                // The parse is done, so this is never on the edit path.
                self.updateCitations()
            }
            self.scheduleStatusUpdate()
            self.lineRuler.needsDisplay = true
            if self.viewMode != .write {
                self.schedulePreviewUpdate()
            }
        }
        editor.onSelectionChange = { [weak self] in
            guard let self else { return }
            self.scheduleStatusUpdate()
            self.lineRuler.needsDisplay = true
        }
        editor.onViewportChange = { [weak self] in
            self?.syncPreviewToEditor()
        }
        previewTextView.onScroll = { [weak self] in
            self?.syncEditorToPreview()
        }
        citations.onReport = { [weak self] report in
            self?.apply(report)
        }
        referencesView.onInsert = { [weak self] key in
            self?.insertCitation(key: key)
        }
        referencesView.onLeave = { [weak self] in
            self?.leaveColumn()
        }
        rightColumn.onEscape = { [weak self] in
            self?.leaveColumn()
        }
        columnTabs.onSelect = { [weak self] index in
            self?.selectColumn(ColumnTab(rawValue: index) ?? .preview)
        }
        refreshCompanion()
        statusBar.onExerciseClick = { [weak self] in
            self?.showChecklist()
        }
        editor.onOptionClick = { [weak self] location in
            self?.explain(at: location)
        }
        statusBar.onNotesClick = { [weak self] in
            self?.showNotes()
        }
        editor.trackPointer()
        editor.onPointerLocation = { [weak self] location in
            self?.pair(editorLocation: location)
        }
        previewTextView.onPointerBlock = { [weak self] block in
            self?.pair(previewBlock: block)
        }
    }

    // MARK: - Citations

    func updateCitations() {
        citations.update(
            source: editor.source,
            documentURL: loomingsDocument?.citationDocumentURL,
            allowPaths: citationPathsAllowed
        )
        syncRightColumn()
        guard citations.isActive else {
            editor.clearCitations()
            updateNoteCount()
            return
        }
        // Undo can bring back the text of the last report. No new report
        // comes for that text, so the dropped marks come from the last one.
        if let report = citations.latestResult?.report, editor.citationRanges.count != report.citations.count {
            applyMarks(of: report, keys: editor.citationKeys)
            updateNoteCount()
        }
    }

    private func apply(_ report: CitationReport) {
        refreshPreview()
        updateLibrary()
        applyMarks(of: report, keys: report.library.map {
            CitationCompletion(key: $0.key, authors: $0.authors, year: $0.year, title: $0.title)
        })
        updateNoteCount()
    }

    private func applyMarks(of report: CitationReport, keys: [CitationCompletion]) {
        guard let source = citations.latestResult?.source else { return }
        editor.setCitations(
            report.citations.map {
                CitationMark(range: NSRange(location: $0.from, length: $0.to - $0.from), isUnknown: !$0.missing.isEmpty)
            },
            keys: keys,
            reportedSource: source
        )
    }

    /// The notes of the newest report, in the current text. A note goes when
    /// an edit touches its place; the next report brings it back.
    private func citationNotes() -> [DocumentNote] {
        guard let latest = citations.latestResult else { return [] }
        let notes = latest.report.documentNotes
        guard notes.contains(where: { $0.range != nil }),
              let change = TextChange.between(latest.source, editor.source) else {
            return notes
        }
        return notes.compactMap { note in
            guard let range = note.range else { return note }
            var moved = note
            moved.range = change.map(range)
            return moved.range == nil ? nil : moved
        }
    }

    /// Asks for a file in the place of `name`, a missing file.
    private func chooseCitationFile(named name: String) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["bib", "csl"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.message = "Choose the file for \(name)."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.useCitationFile(url, for: name)
        }
    }

    /// Writes the file in the frontmatter in the place of the missing `name`.
    func useCitationFile(_ url: URL, for name: String) {
        let path = CitationFileName.value(
            for: url,
            folder: loomingsDocument?.citationDocumentURL?.deletingLastPathComponent()
        )
        changeFrontmatter { engine, source in
            let change = try engine.fileChange(source, name: name, path: path)
            return try engine.setMeta(source, key: change.key, value: change.value)
        }
    }

    /// Sets one citation key of the frontmatter. A nil value removes the key.
    func setCitationMeta(key: String, value: String?) {
        changeFrontmatter { engine, source in
            try engine.setMeta(source, key: key, value: value)
        }
    }

    // MARK: - References menu

    /// Why a chosen file cannot be used.
    private enum CitationChoiceError: Error, CustomStringConvertible {
        case style(String)

        var description: String {
            switch self {
            case .style(let reason): return reason
            }
        }
    }

    /// The folder for a chosen file. An untitled or shelf document has none,
    /// so its paths are absolute.
    private var citationFolder: URL? {
        loomingsDocument?.citationDocumentURL?.deletingLastPathComponent()
    }

    private func chooseFile(type: String, message: String, then use: @escaping (URL) -> Void) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: type)].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.message = message
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            use(url)
        }
    }

    @objc func chooseBibliography(_ sender: Any?) {
        chooseFile(type: "bib", message: "Choose a BibTeX file for this document.") { [weak self] url in
            self?.addBibliography(url)
        }
    }

    /// Adds the file to `bibliography`. The frontmatter comes when it is needed.
    func addBibliography(_ url: URL) {
        let path = CitationFileName.value(for: url, folder: citationFolder)
        changeFrontmatter { engine, source in
            try engine.addBibliography(source, path: path)
        }
    }

    @objc func chooseBundledStyle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setChoice(key: "csl", value: id)
    }

    @objc func chooseLanguage(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        setChoice(key: "lang", value: tag)
    }

    private func setChoice(key: String, value: String) {
        changeFrontmatter { engine, source in
            try engine.setChoice(source, key: key, value: value)
        }
    }

    @objc func chooseStyleFile(_ sender: Any?) {
        chooseFile(type: "csl", message: "Choose a CSL style for this document.") { [weak self] url in
            self?.useStyleFile(url)
        }
    }

    /// Sets the style file. The plan of the citation code reads the file as a
    /// document would: a dependent style with no parent gives a sheet, and
    /// nothing is written.
    func useStyleFile(_ url: URL) {
        let folder = citationFolder
        let path = CitationFileName.value(for: url, folder: folder)
        changeFrontmatter { engine, source in
            let request = CitationSourceRequest(bibliography: [], csl: path, lang: nil)
            let load = try CitationSourceReader.load(request, folder: folder, engine: engine)
            if let reason = load.sources.styleError { throw CitationChoiceError.style(reason) }
            return try engine.setMeta(source, key: "csl", value: path)
        }
    }

    /// The checked items for one text. The answer comes from the citation
    /// queue, so a menu that opens for a new text gets its marks a moment later.
    private var referenceChoices: (source: String, choices: CitationChoices)?

    private var currentChoices: CitationChoices? {
        guard let referenceChoices, (referenceChoices.source as NSString).isEqual(to: editor.source) else { return nil }
        return referenceChoices.choices
    }

    /// Calls `done` when the menu can show the marks of the current text. The
    /// first call for a document with no citations starts its engine.
    func refreshReferenceChoices(then done: @escaping () -> Void) {
        guard currentChoices == nil else {
            done()
            return
        }
        let source = editor.source
        citations.change(source: source) { engine, text in
            try engine.referenceChoices(text)
        } completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let choices):
                self.referenceChoices = (source, choices)
                done()
            case .failure:
                self.markupOverlay.show("The References menu cannot show the current choices.")
            }
        }
    }

    // MARK: - References column

    /// What the control at the top of the right column selects.
    private enum ColumnTab: Int {
        case preview
        case references
    }

    private static let columnTabsInset: CGFloat = 8

    /// Stays through mode changes, for each window, as on the web.
    private var columnTab = ColumnTab.preview
    /// The writer asked for the library, so the control stays with this window.
    private var askedForReferences = false

    /// Only Split has the control: Preview always shows the preview.
    private var showsColumnTabs: Bool {
        viewMode == .split && EditorPreferences.referencesEnabled && (askedForReferences || citations.isActive)
    }

    private var isLibraryShown: Bool { showsColumnTabs && columnTab == .references }

    /// Show References goes to Split with the library. In Split it switches.
    @objc func toggleReferences(_ sender: Any?) {
        guard EditorPreferences.referencesEnabled else { return }
        askedForReferences = true
        if viewMode == .split {
            selectColumn(isLibraryShown ? .preview : .references)
        } else {
            columnTab = .references
            setViewMode(.split)
        }
        if isLibraryShown {
            window?.makeFirstResponder(referencesView.filterField)
        } else {
            leaveColumn()
        }
    }

    private func selectColumn(_ tab: ColumnTab) {
        columnTab = tab
        applyRightColumn()
        if !isLibraryShown {
            refreshPreview()
            layoutPreview()
        }
    }

    /// Escape in the column. Preview has no editor to go to.
    private func leaveColumn() {
        guard viewMode == .split else { return }
        window?.makeFirstResponder(editor.textView)
    }

    /// Puts the control and the preview or the library in the right column.
    /// The divider stays where the writer put it.
    private func applyRightColumn() {
        let showRight = viewMode != .write
        let showTabs = showsColumnTabs
        let showLibrary = isLibraryShown
        clearPairing()
        rightColumn.isHidden = !showRight
        columnTabs.isHidden = !showTabs
        columnTabs.selectedIndex = columnTab.rawValue
        columnTop.constant = showTabs ? ModeSwitch.height + Self.columnTabsInset * 2 : 0
        previewScrollView.isHidden = !showRight || showLibrary
        referencesView.isHidden = !showLibrary
        updateLibrary()
    }

    /// The citation keys of the text decide if the control shows, so an edit
    /// can change the column.
    private func syncRightColumn() {
        guard columnTabs.isHidden == showsColumnTabs || referencesView.isHidden == isLibraryShown else {
            updateLibrary()
            return
        }
        let wasLibrary = !referencesView.isHidden
        applyRightColumn()
        if wasLibrary, !isLibraryShown {
            refreshPreview()
            layoutPreview()
        }
    }

    private func updateLibrary() {
        guard isLibraryShown else { return }
        referencesView.update(
            report: citations.latestResult?.report,
            waiting: citations.isActive && citations.latestResult == nil
        )
    }

    /// Inserts a citation of `key` at the end of the selection, by the rule of
    /// the citation code: one edit, one Undo. The focus goes back to the
    /// editor.
    func insertCitation(key: String) {
        let source = editor.source
        let position = NSMaxRange(editor.textView.selectedRange())
        citations.change(source: source) { engine, text in
            try engine.insertCitation(text, position: position, key: key)
        } completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let insertion):
                // The writer can type or move the caret during the work.
                guard self.editor.source == source,
                      NSMaxRange(self.editor.textView.selectedRange()) == position else {
                    self.insertCitation(key: key)
                    return
                }
                self.place(insertion)
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "The citation could not be inserted."
                alert.informativeText = String(describing: error)
                self.present(alert)
            }
        }
    }

    private func place(_ insertion: CitationInsertion) {
        let textView = editor.textView
        let range = NSRange(location: insertion.from, length: 0)
        textView.breakUndoCoalescing()
        guard editor.replace(range: range, with: insertion.insert) else { return }
        textView.breakUndoCoalescing()
        let caret = NSRange(location: insertion.from + (insertion.insert as NSString).length, length: 0)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
        window?.makeFirstResponder(textView)
    }

    var isLibraryShownForTesting: Bool { isLibraryShown && !referencesView.isHidden }
    var columnTabsForTesting: ModeSwitch? { columnTabs.isHidden ? nil : columnTabs }
    var previewTextViewForTesting: NSTextView { previewTextView }
    /// The left edge of the editor pane, and of the page in it.
    var editorEdgesForTesting: (pane: CGFloat, page: CGFloat) { (scrollView.frame.minX, scrollView.contentView.bounds.minX) }
    /// The widths of the editor and the right column.
    var columnWidthsForTesting: (editor: CGFloat, right: CGFloat) { (scrollView.frame.width, rightColumn.frame.width) }
    var referencesViewForTesting: ReferencesView { referencesView }
    /// The last sheet of a refused choice.
    private(set) var choiceAlertForTesting: NSAlert?

    /// Applies `edit` as one undoable edit that covers only the text that
    /// differs, so the caret and the rest of the document stay in place. When
    /// the writer types during the work, the work starts again on the new text.
    private func changeFrontmatter(_ edit: @escaping CitationController.TextEdit) {
        let source = editor.source
        citations.change(source: source, with: edit) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let changed):
                guard self.editor.source == source else {
                    self.changeFrontmatter(edit)
                    return
                }
                guard let change = TextChange.between(source, changed) else { return }
                self.editor.textView.breakUndoCoalescing()
                self.editor.replace(range: change.range, with: change.replacement(in: changed))
                self.editor.textView.breakUndoCoalescing()
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = error is CitationChoiceError
                    ? "This style cannot be used."
                    : "The frontmatter could not be changed."
                alert.informativeText = String(describing: error)
                self.choiceAlertForTesting = alert
                self.present(alert)
            }
        }
    }

    /// False for a document from a share link that is not saved.
    private var citationPathsAllowed: Bool {
        loomingsDocument?.cameFromShareLink != true
    }

    /// One export, fixed when it starts: the page and the share link come from
    /// one text, and the writer can type during the wait.
    private struct ExportPage {
        let source: String
        /// The text of the share link: the source with the cited entries.
        let shareSource: String
        let markdown: String
        /// The reference list that ends `markdown`.
        var bibliography = ""
        let documentURL: URL?
        let title: String
    }

    private var currentPage: ExportPage {
        let source = editor.source
        return ExportPage(
            source: source,
            shareSource: source,
            markdown: citations.report(for: source)?.markdownSource ?? source,
            bibliography: citations.report(for: source)?.bibliographyMarkdown ?? "",
            documentURL: loomingsDocument?.linkBaseURL,
            title: exportTitle
        )
    }

    /// Runs `body` with the text to export: the source with its citations
    /// formatted when the report for this text comes in time. The closure
    /// holds this window controller on purpose: a window that closes during
    /// the wait still gets its file, and the export limit bounds the wait.
    /// - Parameters:
    ///   - statusFirst: the status comes before `body`, not after it.
    ///   - sharing: the page has a share link. Its text gets the rest of the
    ///     export limit, so one export never waits twice.
    private func withExportPage(
        statusFirst: Bool = false,
        sharing: Bool = false,
        _ body: @escaping (ExportPage) -> Void
    ) {
        let start = currentPage
        let started = Date()
        let finish = { (text: CitationController.ExportText, shared: CitationController.ShareText?) in
            let page = ExportPage(
                source: start.source,
                shareSource: shared?.source ?? start.source,
                markdown: text.markdown,
                bibliography: text.bibliography,
                documentURL: start.documentURL,
                title: start.title
            )
            let status = text.status ?? shared?.failure
            self.exportStatus = status
            if statusFirst {
                self.showExportStatus(status) { body(page) }
            } else {
                body(page)
                self.showExportStatus(status)
            }
        }
        citations.exportText(
            source: start.source,
            documentURL: loomingsDocument?.citationDocumentURL,
            allowPaths: citationPathsAllowed
        ) { text in
            guard sharing else {
                finish(text, nil)
                return
            }
            let left = max(0, self.citations.exportLimit - Date().timeIntervalSince(started))
            self.citations.shareText(
                source: start.source,
                documentURL: self.loomingsDocument?.citationDocumentURL,
                allowPaths: self.citationPathsAllowed,
                limit: left
            ) { shared in
                finish(text, shared)
            }
        }
    }

    private func showExportStatus(_ status: String?, then next: @escaping () -> Void = {}) {
        guard let status, showsExportStatusSheet else {
            next()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Check the citations in this export."
        alert.informativeText = status
        present(alert, then: next)
    }

    /// A sheet when the window is open. An export can end after its window
    /// closes, and then the alert has no window.
    private func present(_ alert: NSAlert, then next: @escaping () -> Void = {}) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window) { _ in next() }
        } else {
            afterMainQueueBlock {
                alert.runModal()
                next()
            }
        }
    }

    /// An export can end inside a block on the main queue. A modal run there
    /// holds each later block of the queue until the modal ends, so a modal
    /// run must start from the run loop.
    private func afterMainQueueBlock(_ work: @escaping () -> Void) {
        RunLoop.main.perform { MainActor.assumeIsolated(work) }
    }

    private(set) var exportStatus: String?
    var showsExportStatusSheet = true
    var printHookForTesting: ((HandoutTextView) -> Void)?

    /// The text of the last render that reached the preview pipeline.
    private(set) var previewInputForTesting: String?
    private(set) var previewRendersForTesting = 0
    /// The renders that began on the preview queue; a stale one never does.
    var previewRendersStartedForTesting: Int { previewTicket.started }
    var sidebarListingsForTesting: Int { sidebar.listingsForTesting }
    func refreshPreviewForTesting() { refreshPreview() }
    /// Keeps the preview queue busy, so later renders wait behind it.
    func blockPreviewQueueForTesting(_ seconds: TimeInterval) {
        previewQueue.async { Thread.sleep(forTimeInterval: seconds) }
    }

    // MARK: - View modes and preview

    @objc func setWriteMode(_ sender: Any?) {
        setViewMode(.write)
    }

    @objc func setSplitMode(_ sender: Any?) {
        setViewMode(.split)
    }

    @objc func setPreviewMode(_ sender: Any?) {
        setViewMode(.preview)
    }

    @objc func toggleSplitMode(_ sender: Any?) {
        setViewMode(viewMode == .split ? .write : .split)
    }

    @objc func togglePreviewMode(_ sender: Any?) {
        setViewMode(viewMode == .preview ? .write : .preview)
    }

    @objc func changeViewMode(_ sender: NSSegmentedControl) {
        setViewMode(ViewMode(rawValue: sender.selectedSegment) ?? .write)
    }

    func setViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        applyViewMode()
    }

    // MARK: - Teaching: checker notes

    private var report: TeachingReport? { editor.companionResult as? TeachingReport }

    /// The report matches the text only when the last parse is current.
    private var currentReport: TeachingReport? {
        editor.lastAppliedRevision == editor.revision ? report : nil
    }

    /// Rebuilds the teaching companion with the document's attached checks.
    func refreshCompanion() {
        let attached = loomingsDocument?.attachedChecks
        editor.companionAnalysis = { source in TeachingReport.make(source: source, attached: attached) }
        editor.reanalyze()
    }

    private func showChecklist() {
        guard let report = currentReport, !(report.checkResults.isEmpty && report.directiveNotes.isEmpty) else { return }
        let content = TeachingPopovers.checklist(report.checkResults, notes: report.directiveNotes)
        TeachingPopovers.show(content, relativeTo: statusBar.bounds, of: statusBar, palette: ThemeManager.shared.resolved())
    }

    var exerciseTitleForTesting: String? { statusBar.exerciseTitle }

    // MARK: - Teaching: section limits

    /// The innermost limited section around the caret.
    private func updateSectionStatus(caret: Int) {
        // Between an edit and its parse there is no current report; keep the
        // last count rather than blink it away while the student types.
        guard let report = currentReport else { return }
        let section = report.sections
            .filter { $0.limit != nil && (NSLocationInRange(caret, $0.range) || NSMaxRange($0.range) == caret) }
            .max { $0.heading.level < $1.heading.level }
        if let section, let limit = section.limit {
            statusBar.setSection(title: section.heading.title, words: section.words, limit: limit)
        } else {
            statusBar.setSection(title: nil, words: 0, limit: 0)
        }
    }

    /// Outline entries with each section's words, and its limit when set.
    private func outlineEntries() -> [(item: OutlineItem, title: String)] {
        let source = editor.source
        let sections = SectionStatistics.sections(source, outline: editor.outline, limits: TeachingReport.limits(in: source).limits)
        return sections.map { section in
            let name = section.heading.title.isEmpty ? "(empty heading)" : section.heading.title
            let count = section.limit.map { "\(section.words)/\($0)" } ?? "\(section.words)"
            return (section.heading, "\(name) \u{2014} \(count)")
        }
    }

    var sectionTitleForTesting: String? { statusBar.sectionTitle }
    var outlineTitlesForTesting: [String] { outlineEntries().map(\.title) }

    private func applyTeachingReport() {
        if let report = currentReport {
            statusBar.setExercise(
                passed: report.checkResults.filter(\.passed).count,
                total: report.checkResults.count,
                notes: report.directiveNotes.count
            )
        }
        let issues = currentReport?.lintIssues ?? []
        let tint = ThemeManager.shared.resolved()?.colors.accentColor ?? .systemOrange
        editor.textView.setDecorations(
            issues.map { EditorDecoration(range: $0.range, style: .squiggle(tint)) },
            for: "notes"
        )
        lintNoteCount = issues.count
        updateNoteCount()
    }

    /// The count of the last parse. A citation report can come between an
    /// edit and its parse, and the checker's notes must not go away then.
    private var lintNoteCount = 0

    private func updateNoteCount() {
        statusBar.setNotes(count: lintNoteCount + citationNotes().count)
    }

    /// The notes for the current text.
    private var currentNotes: [DocumentNote] {
        DocumentNote.merged(lint: currentReport?.lintIssues ?? [], citation: citationNotes())
    }

    private var notesPopover: NSPopover?

    private func showNotes(_ only: [DocumentNote]? = nil) {
        let notes = only ?? currentNotes
        guard !notes.isEmpty else { return }
        let content = TeachingPopovers.notes(
            notes,
            line: { [weak self] in self?.editor.lineNumber(at: $0.location) ?? 1 },
            onFix: { [weak self] in self?.fixFromNotes($0) },
            onGo: { [weak self] in self?.reveal($0) },
            onChooseFile: { [weak self] name in
                self?.notesPopover?.close()
                self?.chooseCitationFile(named: name)
            }
        )
        notesPopover?.close()
        if let only, let range = only.first?.range,
           let rect = editor.textView.segmentFrames(for: range).first {
            notesPopover = TeachingPopovers.show(content, relativeTo: rect, of: editor.textView, palette: ThemeManager.shared.resolved())
        } else {
            notesPopover = TeachingPopovers.show(content, relativeTo: statusBar.bounds, of: statusBar, palette: ThemeManager.shared.resolved())
        }
    }

    /// A fix changes the text, so every other note's range is out of date:
    /// the list closes rather than leave buttons that can no longer work.
    private func fixFromNotes(_ issue: LintIssue) {
        apply(fixOf: issue)
        notesPopover?.close()
        notesPopover = nil
    }

    func showNotesForTesting() { showNotes() }
    func closeNotesForTesting() { notesPopover?.close() }
    var noteMessagesForTesting: [String] { currentNotes.map(\.message) }
    /// The titles of the buttons in the open list of notes.
    var noteButtonsForTesting: [String] {
        func buttons(in view: NSView) -> [String] {
            view.subviews.flatMap { subview -> [String] in
                ((subview as? NSButton).map { [$0.title] } ?? []) + buttons(in: subview)
            }
        }
        return notesPopover?.contentViewController.map { buttons(in: $0.view) } ?? []
    }
    var isNotesPopoverShownForTesting: Bool { notesPopover?.isShown ?? false }
    func fixFromNotesPopoverForTesting(_ index: Int) {
        guard let issues = currentReport?.lintIssues, issues.indices.contains(index) else { return }
        fixFromNotes(issues[index])
    }
    func updateStatusNowForTesting() { updateStatus() }

    private func apply(fixOf issue: LintIssue) {
        guard let fix = issue.fix, currentReport?.lintIssues.contains(issue) == true else { return }
        editor.replace(range: fix.range, with: fix.replacement)
    }

    private func reveal(_ range: NSRange) {
        window?.makeFirstResponder(editor.textView)
        editor.textView.setSelectedRange(NSRange(location: range.location, length: 0))
        editor.textView.scrollRangeToVisible(range)
    }

    /// Option-click: a note under the pointer first, else what the marker means.
    private func explain(at location: Int) {
        let here = currentNotes.filter { note in
            note.range.map { NSLocationInRange(location, $0) || NSMaxRange($0) == location } ?? false
        }
        if !here.isEmpty {
            showNotes(here)
            return
        }
        guard let (span, explanation) = explanation(at: location) else { return }
        let lesson = explanation.lesson
        let content = TeachingPopovers.explanation(explanation, onLesson: lesson.map { file in
            { (NSApp.delegate as? AppDelegate)?.openLesson(named: file) }
        })
        let rect = editor.textView.segmentFrames(for: span.range).first
            ?? NSRect(x: 0, y: 0, width: 1, height: 1)
        TeachingPopovers.show(content, relativeTo: rect, of: editor.textView, palette: ThemeManager.shared.resolved())
    }

    private func explanation(at location: Int) -> (MarkdownSyntaxSpan, MarkerExplanation)? {
        guard let span = editor.span(at: location) else { return nil }
        let text = editor.source as NSString
        guard NSMaxRange(span.range) <= text.length else { return nil }
        let marker = text.substring(with: span.range)
        guard let explanation = MarkerGlossary.explain(kind: span.kind, marker: marker) else { return nil }
        return (span, explanation)
    }

    func explanationTitleForTesting(at location: Int) -> String? {
        explanation(at: location)?.1.title
    }

    var notesForTesting: [String] { currentReport?.lintIssues.map(\.rule) ?? [] }
    var statusNotesTitleForTesting: String? { statusBar.notesTitle }
    func applyNoteFixForTesting(_ index: Int) {
        guard let issues = currentReport?.lintIssues, issues.indices.contains(index) else { return }
        apply(fixOf: issues[index])
    }

    // MARK: - Writing history

    let history = HistoryRecorder()
    private var replayController: ReplayWindowController?

    func windowDidBecomeKey(_ notification: Notification) {
        history.forgetHistoryAnswer()
        refreshSidebar()
    }

    func windowWillClose(_ notification: Notification) {
        if let featuresObserver { NotificationCenter.default.removeObserver(featuresObserver) }
        featuresObserver = nil
        history.flush()
        citations.close()
        replayController?.close()
        removeSentFiles()
    }

    @objc func toggleWritingHistory(_ sender: Any?) {
        guard let url = loomingsDocument?.fileURL else { return }
        history.setRecording(!history.isRecording, fileURL: url, text: editor.source)
    }

    @objc func replayWritingHistory(_ sender: Any?) {
        history.flush()
        let entries = history.entries(fileURL: loomingsDocument?.fileURL)
        guard !entries.isEmpty else { return }
        replayController?.close()
        let controller = ReplayWindowController(entries: entries, title: exportTitle, palette: ThemeManager.shared.resolved())
        replayController = controller
        controller.showWindow(nil)
    }

    @objc func deleteWritingHistory(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the writing history of \u{201C}\(exportTitle)\u{201D}?"
        alert.informativeText = "The replay can no longer be shown, and recording stops. The document itself is not changed."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.replayController?.close()
            self.history.deleteHistory(fileURL: self.loomingsDocument?.fileURL)
        }
    }

    // MARK: - Compare With

    private var compareControllers: [CompareWindowController] = []

    /// Opens the comparison of another text (left) with this document (right).
    @discardableResult
    func compare(withText text: String, title: String) -> CompareWindowController {
        let controller = CompareWindowController(
            leftTitle: title,
            leftText: text,
            rightTitle: exportTitle,
            rightText: editor.source,
            palette: ThemeManager.shared.resolved()
        )
        compareControllers.append(controller)
        controller.showWindow(nil)
        return controller
    }

    @objc func compareWithDocument(_ sender: NSMenuItem) {
        guard let other = sender.representedObject as? LoomingsDocument,
              let otherController = other.windowControllers.first as? EditorWindowController else { return }
        compare(withText: otherController.editor.source, title: otherController.exportTitle)
    }

    @objc func compareWithFile(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let file = try TextFileCodec.decode(Data(contentsOf: url))
                self.compare(withText: file.text, title: url.deletingPathExtension().lastPathComponent)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    // MARK: - Projector mode

    private(set) var isProjectorMode = false
    private let markupOverlay = MarkupOverlay()

    @objc func toggleProjectorMode(_ sender: Any?) {
        isProjectorMode.toggle()
        editor.onMarkupUsed = isProjectorMode ? { [weak self] phrase in self?.markupOverlay.show(phrase) } : nil
        if !isProjectorMode { markupOverlay.dismiss() }
        applyPreferences()
        if viewMode != .write { layoutPreview() }
    }

    private var effectiveShowLineNumbers: Bool { EditorPreferences.showLineNumbers && !isProjectorMode }
    private var effectiveColumnWidth: ColumnWidth { isProjectorMode ? ProjectorMode.columnWidth : EditorPreferences.columnWidth }

    private func previewTheme(_ resolved: ResolvedPalette?) -> PreviewTheme {
        let size: CGFloat = isProjectorMode ? ProjectorMode.previewBodySize : 17
        return resolved.map { PreviewTheme.themed($0, bodySize: size) } ?? .standard
    }

    private func installOverlay() {
        markupOverlay.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(markupOverlay)
        NSLayoutConstraint.activate([
            markupOverlay.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            markupOverlay.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -24),
            markupOverlay.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, constant: -48),
        ])
    }

    var isStatusBarHiddenForTesting: Bool { statusBar.isHidden }
    /// The editor column's left inset and width.
    var editorColumnForTesting: NSSize {
        NSSize(
            width: editor.textView.textContainerInset.width,
            height: editor.textView.textLayoutManager?.textContainer?.containerSize.width ?? 0
        )
    }
    func layoutNowForTesting() {
        containerView.layoutSubtreeIfNeeded()
        applyColumnWidth()
    }
    func moveDividerForTesting(toFraction fraction: CGFloat) {
        splitView.setPosition((splitView.bounds.width * fraction).rounded(), ofDividerAt: 0)
    }
    var areLineNumbersVisibleForTesting: Bool { scrollView.rulersVisible }
    var overlayTextForTesting: String? { markupOverlay.text }
    func showOverlayForSnapshot(_ text: String) { markupOverlay.show(text) }
    var previewBodyFontSizeForTesting: CGFloat? {
        guard let storage = previewTextView.textStorage, storage.length > 0 else { return nil }
        return (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
    }

    // MARK: - Split divider

    /// Dragging the divider resizes both panes; lay both columns out again.
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard window != nil, viewMode == .split else { return }
        applyColumnWidth()
        layoutPreview()
    }

    // MARK: - File sidebar

    @objc func toggleSidebar(_ sender: Any?) {
        guard EditorPreferences.sidebarEnabled else { return }
        sidebarShown.toggle()
        applySidebar()
    }

    /// The sidebar is a quick switcher, not a pane: it steps aside when the
    /// writer clicks into the text, types, or opens a file.
    func hideSidebarForWriting() {
        guard sidebarShown else { return }
        sidebarShown = false
        applySidebar()
    }

    var isSidebarVisibleForTesting: Bool { sidebarOn }
    var sidebarRowsForTesting: [String] { sidebar.rowNamesForTesting }
    var sidebarSelectionForTesting: String? { sidebar.selectedNameForTesting }
    var sidebarFolderForTesting: URL? { sidebar.folder }
    func clickSidebarRowForTesting(named name: String) { sidebar.clickRowForTesting(named: name) }

    /// The folder this window lists. A shared folder is one setting. Otherwise
    /// the window's own choice, then the folder of its file, then the last one
    /// chosen anywhere.
    private var sidebarFolderToShow: URL? {
        if EditorPreferences.sidebarSharedFolder { return EditorPreferences.sidebarFolder }
        return sidebarFolderOverride
            ?? loomingsDocument?.fileURL?.deletingLastPathComponent()
            ?? EditorPreferences.sidebarFolder
    }

    /// Shows or hides the sidebar, and lists the folder when it shows. The card
    /// fades in and out; the editor does not move.
    func applySidebar() {
        let show = EditorPreferences.sidebarEnabled && sidebarShown
        // A file opened from another window's sidebar lists the folder that
        // window was browsing, not the folder of the file.
        if sidebarFolderOverride == nil, let handed = SidebarHandoff.take(for: loomingsDocument?.fileURL) {
            sidebarFolderOverride = EditorPreferences.sidebarSharedFolder ? nil : handed
        }
        syncFilesToolbarItem()
        if show {
            if sidebar.folder != sidebarFolderToShow || !sidebarOn {
                sidebar.showFolder(sidebarFolderToShow)
            }
            sidebar.select(url: loomingsDocument?.fileURL)
        }
        if show != sidebarOn {
            sidebarOn = show
            sidebar.setShown(show, animated: window?.isVisible == true)
        }
    }

    /// The window's own list, listed again: files come and go outside the app.
    func refreshSidebar() {
        guard sidebarOn else { return }
        sidebar.reloadIfChanged()
        sidebar.select(url: loomingsDocument?.fileURL)
    }

    /// Settings changed: References and the sidebar follow at once.
    private func featuresChanged() {
        applySidebar()
        updateCitations()
        applyRightColumn()
        if viewMode != .write { refreshPreview() }
    }

    private func openFromSidebar(_ url: URL) {
        if url.standardizedFileURL == loomingsDocument?.fileURL?.standardizedFileURL { return }
        SidebarHandoff.remember(folder: sidebar.folder, for: url)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
        hideSidebarForWriting()
    }

    private func chooseSidebarFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to list in the sidebar."
        panel.directoryURL = sidebar.folder ?? EditorPreferences.sidebarFolder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.setSidebarFolder(url)
        }
    }

    func setSidebarFolder(_ url: URL) {
        EditorPreferences.sidebarFolder = url
        sidebarFolderOverride = EditorPreferences.sidebarSharedFolder ? nil : url
        if EditorPreferences.sidebarSharedFolder {
            NotificationCenter.default.post(name: .loomingsFeaturesChanged, object: nil)
        } else {
            applySidebar()
        }
    }

    // MARK: - Paired lines

    /// Split view only: the source under the pointer lights its preview block.
    private func pair(editorLocation location: Int?) {
        guard viewMode == .split, !isLibraryShown, let location else {
            previewTextView.highlightedBlockIndex = nil
            return
        }
        previewTextView.highlightedBlockIndex = PreviewDocument.blockIndex(
            in: previewTextView.blocks,
            containing: citationLines?.markdownLocation(forSource: location) ?? location
        )
    }

    /// Split view only: the preview block under the pointer lights its source.
    private func pair(previewBlock block: PreviewBlock?) {
        guard viewMode == .split, !isLibraryShown else {
            editor.pairedRange = nil
            return
        }
        editor.pairedRange = block.flatMap(sourceRange(of:))
    }

    /// A block's range in the editor. With citations, a block's range is in
    /// the formatted text, and the reference list has no source.
    private func sourceRange(of block: PreviewBlock) -> NSRange? {
        guard let citationLines else { return block.sourceRange }
        return citationLines.sourceRange(forMarkdown: block.sourceRange)
    }

    private func clearPairing() {
        previewTextView.highlightedBlockIndex = nil
        editor.pairedRange = nil
    }

    func pairForTesting(editorLocation location: Int) { pair(editorLocation: location) }
    func pairForTesting(previewBlockAt index: Int) {
        pair(previewBlock: previewTextView.blocks.indices.contains(index) ? previewTextView.blocks[index] : nil)
    }
    var previewBlockCountForTesting: Int { previewTextView.blocks.count }
    var previewHighlightedBlockKind: String? {
        previewTextView.highlightedBlockIndex.map { previewTextView.blocks[$0].kind.rawValue }
    }
    var editorPairedRange: NSRange? { editor.pairedRange }

    /// Lights both sides of one pair at once, for design snapshots.
    func pairBothForSnapshot(editorLocation location: Int) {
        pair(editorLocation: location)
        if let index = previewTextView.highlightedBlockIndex {
            editor.pairedRange = sourceRange(of: previewTextView.blocks[index])
        }
    }

    private func applyViewMode() {
        clearPairing()
        let showEditor = viewMode != .preview
        let showPreview = viewMode != .write

        scrollView.isHidden = !showEditor
        applyRightColumn()
        modeSwitch?.selectedIndex = viewMode.rawValue
        splitView.adjustSubviews()

        if showPreview {
            refreshPreview()
        }
        // Every mode lays the editor column out for its pane once the split
        // view has settled; leaving Split must give it the whole width back.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.viewMode == .split {
                self.splitView.setPosition(self.splitView.bounds.width / 2, ofDividerAt: 0)
            }
            self.splitView.layoutSubtreeIfNeeded()
            self.applyColumnWidth()
            if self.viewMode != .write {
                self.layoutPreview()
            }
        }
        if showEditor {
            if viewMode == .write {
                window?.makeFirstResponder(editor.textView)
            }
        }
    }

    private func layoutPreview() {
        let width = previewScrollView.contentSize.width
        guard width > 0 else { return }
        let top = previewTextView.topSourceLine()
        previewTextView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: previewTextView.frame.height)
        )
        // The preview keeps a reading measure (about 75 characters of the
        // serif) instead of running prose across a wide window.
        let measure = effectiveColumnWidth.maxWidth * 0.9
        let containerWidth = max(120, min(measure, width - 48))
        previewTextView.textContainerInset = NSSize(
            width: max(24, ((width - containerWidth) / 2).rounded(.down)),
            height: 28
        )
        if let container = previewTextView.textContainer {
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        previewTextView.resizeToFit()
        if let top {
            DispatchQueue.main.async { [weak self] in
                self?.previewTextView.scroll(toSourceLine: top)
            }
        }
    }

    private func schedulePreviewUpdate() {
        guard viewMode != .write, !isLibraryShown else { return }
        previewWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshPreview()
        }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func refreshPreview() {
        guard viewMode != .write, !isLibraryShown else { return }
        let source = editor.source
        var markdown = source
        switch citations.previewText(for: source) {
        case .render(let text):
            markdown = text
        case .keepLast:
            // The report comes soon. Literal keys must not flash until then.
            if !previewTextView.blocks.isEmpty { return }
        }
        previewInputForTesting = markdown
        previewRendersForTesting += 1
        previewGeneration += 1
        let generation = previewGeneration
        previewTicket.set(generation)
        let ticket = previewTicket
        let documentURL = loomingsDocument?.linkBaseURL
        let resolved = ThemeManager.shared.resolved()
        let theme = previewTheme(resolved)

        let pipeline = previewPipeline
        previewQueue.async { [weak self] in
            guard ticket.start(generation) else { return }
            let rendered = pipeline.render(
                source: markdown,
                documentURL: documentURL,
                palette: resolved,
                theme: theme
            )
            let lines = markdown == source ? nil : CitationLineMap(source: source, markdown: markdown)
            DispatchQueue.main.async {
                guard let self,
                      generation == self.previewGeneration,
                      self.viewMode != .write else {
                    return
                }
                self.citationLines = lines
                self.previewTextView.render(rendered, documentURL: documentURL)
            }
        }
    }

    private func syncPreviewToEditor() {
        guard viewMode == .split, !isLibraryShown, !isLocked(by: "preview") else { return }
        let visible = editor.visibleCharacterRange()
        let starts = editor.analysis.lineStarts
        guard !starts.isEmpty else { return }

        let line = max(0, editor.lineNumber(at: visible.location) - 1)
        let start = starts.indices.contains(line) ? starts[line] : 0
        let end = starts.indices.contains(line + 1)
            ? starts[line + 1]
            : (editor.textView.textStorage?.length ?? start)
        let fraction = end > start
            ? Double(visible.location - start) / Double(end - start)
            : 0

        lockSync("editor")
        previewTextView.scroll(toSourceLine: Double(line) + min(1, max(0, fraction)))
    }

    private func syncEditorToPreview() {
        guard viewMode == .split, !isLibraryShown, !isLocked(by: "editor") else { return }
        guard let line = previewTextView.topSourceLine() else { return }
        lockSync("preview")
        editor.scrollToLine(Int(floor(max(0, line))) + 1)
    }

    private func lockSync(_ source: String) {
        syncSource = source
        syncUntil = Date().addingTimeInterval(0.12)
    }

    private func isLocked(by source: String) -> Bool {
        syncSource == source && Date() < syncUntil
    }

    // MARK: - Preferences and status

    func applyPreferences() {
        editor.setFontChoice(EditorFontChoice(rawValue: EditorPreferences.editorFont) ?? .jetBrainsMono)
        editor.stylesMarkdown = EditorPreferences.styledMarkdown
        editor.setFontSize(isProjectorMode ? ProjectorMode.editorFontSize : EditorPreferences.fontSize)
        editor.highlightsCurrentLine = isProjectorMode
        editor.setSmartTypography(EditorPreferences.smartTypography)
        editor.setTypewriterMode(EditorPreferences.typewriter)
        applyTheme()
        applyStatusVisibility()
        applyLineNumbersVisibility()
        applyColumnWidth()
        scheduleStatusUpdate()
    }

    private func applyTheme() {
        let resolved = ThemeManager.shared.resolved()
        editor.applyPalette(resolved)
        previewTextView.applyTheme(previewTheme(resolved))
        referencesView.apply(palette: resolved, textSize: isProjectorMode ? ProjectorMode.referencesTextSize : 13)
        sidebar.apply(palette: resolved)
        markupOverlay.applyPalette(resolved)
        lineRuler?.applyPalette(resolved)
        scrollView.backgroundColor = resolved?.colors.background ?? .textBackgroundColor
        previewScrollView.backgroundColor = resolved?.colors.background ?? .textBackgroundColor
        let knobs: NSScroller.KnobStyle = resolved.map { $0.isDark ? .light : .dark } ?? .default
        scrollView.scrollerKnobStyle = knobs
        previewScrollView.scrollerKnobStyle = knobs
        for scroller in [scrollView.verticalScroller, previewScrollView.verticalScroller] {
            (scroller as? ThemedScroller)?.trackColor = resolved?.colors.background
        }
        splitView.themedDividerColor = resolved?.colors.borderColor
        previewTextView.setHighlightColor(
            (resolved?.colors.selectionColor ?? .selectedTextBackgroundColor).withAlphaComponent(0.45)
        )
        statusBar.applyPalette(resolved)
        applyChrome(resolved)
        applyToolbarPalette(resolved)
        if viewMode != .write {
            refreshPreview()
        }
    }

    /// The title bar and toolbar sit on the document's own ground, divided
    /// from it by a hairline, so a parchment page does not wear grey chrome.
    private func applyChrome(_ resolved: ResolvedPalette?) {
        guard let window else { return }
        if let resolved {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = resolved.colors.background
        } else {
            window.titlebarAppearsTransparent = false
            window.backgroundColor = .windowBackgroundColor
        }
        window.titlebarSeparatorStyle = .line
    }

    private func applyStatusVisibility() {
        let visible = EditorPreferences.showStats && !isProjectorMode
        statusBar.isHidden = !visible
        statusHeightConstraint?.constant = visible ? 24 : 0
        scheduleStatusUpdate()
    }

    private func applyLineNumbersVisibility() {
        scrollView.rulersVisible = effectiveShowLineNumbers
        lineRuler?.needsDisplay = true
        applyColumnWidth()
    }

    private func applyColumnWidth() {
        guard let window, window.contentView != nil else { return }
        containerView.layoutSubtreeIfNeeded()

        let rulers = scrollView.rulersVisible && lineRuler != nil
        // Measured from the scroll view's frame: contentSize lags behind a
        // ruler-thickness change until the next tile.
        let scroller = scrollView.scrollerStyle == .legacy && scrollView.hasVerticalScroller
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
        let full = scrollView.frame.width - scroller
        guard full > 0 else { return }

        // The column never takes more than 82% of the width, so a Wide column
        // in a narrow window still leaves a visible margin on both sides.
        let maximum = min(effectiveColumnWidth.maxWidth, (full * 0.82).rounded(.down))
        let inset: CGFloat
        let containerWidth: CGFloat
        if rulers {
            // The ruler takes the whole left margin, so the numbers sit a
            // gutter away from the text and the column stays centred.
            let gutter: CGFloat = 14
            let thickness = max(44, ((full - maximum) / 2 - gutter).rounded(.down))
            if lineRuler.ruleThickness != thickness {
                lineRuler.ruleThickness = thickness
                scrollView.tile()
            }
            let available = full - thickness
            inset = thickness > 44 ? gutter : max(gutter, (available - maximum) / 2)
            containerWidth = max(120, min(maximum, available - inset * 2))
        } else {
            inset = max(24, (full - maximum) / 2)
            containerWidth = max(120, min(maximum, full - inset * 2))
        }

        editor.textView.textContainerInset = NSSize(width: inset, height: 24)
        if let container = editor.textView.textLayoutManager?.textContainer {
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        editor.textView.needsLayout = true
        editor.requestVisibleStyling()
        if viewMode != .write { layoutPreview() }
    }

    var previewText: String { previewTextView.string }
    var previewAccessibilityLabel: String? { previewTextView.accessibilityLabel() }
    var isPreviewVisible: Bool { !previewScrollView.isHidden }
    var isEditorVisible: Bool { !scrollView.isHidden }
    var editorTopLine: Int { editor.lineNumber(at: editor.visibleCharacterRange().location) }
    var previewTopLine: Double? { previewTextView.topSourceLine() }
    var previewContentHeight: CGFloat { previewTextView.frame.height }
    var previewViewportHeight: CGFloat { previewScrollView.contentSize.height }

    func scrollPreviewForTesting(toSourceLine line: Double) {
        previewTextView.scroll(toSourceLine: line)
    }

    /// With no report for the current text, the output has the literal keys.
    func renderedHTMLForTesting() -> String {
        documentHTML(currentPage)
    }

    private func documentHTML(_ page: ExportPage) -> String {
        let rendered = PreviewRenderer().render(source: page.markdown, documentURL: page.documentURL)
        return PreviewHTMLExport.document(
            title: page.title,
            bodyHTML: rendered.html,
            palette: ThemeManager.shared.resolved()
        )
    }

    func renderedPDFForTesting() -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-handout-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        Handout.writePDF(makeHandout(currentPage, includeQR: EditorPreferences.printQRCode), to: url)
        return (try? Data(contentsOf: url)) ?? Data()
    }

    /// - Parameter includeQR: the page ends with the share link as a QR code.
    ///   The caller reads the setting once, so the page and the share link
    ///   built for it agree even if the setting changes during the wait.
    private func makeHandout(_ page: ExportPage, includeQR: Bool) -> HandoutTextView {
        Handout.view(
            source: includeQR ? page.shareSource : nil,
            markdown: page.markdown,
            documentURL: page.documentURL,
            title: page.title
        )
    }

    func refreshStatus() {
        scheduleStatusUpdate()
    }

    private func scheduleStatusUpdate() {
        statusWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.updateStatus()
        }
        statusWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: item)
    }

    private func updateStatus() {
        guard !statusBar.isHidden else { return }

        let selection = editor.textView.selectedRange()
        let line = editor.lineNumber(at: selection.location)
        let starts = editor.analysis.lineStarts
        let lineStart = (line > 0 && line <= starts.count) ? starts[line - 1] : 0
        let column = max(1, selection.location - lineStart + 1)
        let position = "Ln \(line), Col \(column)"

        updateSectionStatus(caret: selection.location)

        if let statistics = editor.selectionStatistics() {
            statusBar.update(position: position, statistics: statistics)
            return
        }

        let analysis = editor.analysis
        statusBar.update(
            position: position,
            words: analysis.wordCount,
            characters: analysis.characterCount,
            lines: analysis.lineCount,
            reading: TextStatistics.readingTime(analysis.wordCount),
            goal: EditorPreferences.wordGoal
        )
    }

    // MARK: - Export and print

    var exportTitle: String {
        let name = loomingsDocument?.displayName ?? "Untitled"
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? name : base
    }

    private func saveURL(name: String, fileExtension: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(name).\(fileExtension)"
        if let type = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [type]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @objc func exportMarkdown(_ sender: Any?) {
        guard let document = loomingsDocument,
              let url = saveURL(name: exportTitle, fileExtension: "md") else {
            return
        }
        do {
            let type = document.fileType ?? "net.daringfireball.markdown"
            let data = try document.data(ofType: type)
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let url = saveURL(name: exportTitle, fileExtension: "html") else {
            return
        }
        exportHTML(to: url)
    }

    func exportHTML(to url: URL, completion: (() -> Void)? = nil) {
        withExportPage { page in
            defer { completion?() }
            do {
                try self.documentHTML(page).data(using: .utf8)?.write(to: url, options: .atomic)
            } catch {
                self.present(NSAlert(error: error))
            }
        }
    }

    @objc func exportDocx(_ sender: Any?) {
        guard let url = saveURL(name: exportTitle, fileExtension: "docx") else {
            return
        }
        exportDocx(to: url)
    }

    func exportDocx(to url: URL, completion: (() -> Void)? = nil) {
        withExportPage { page in
            defer { completion?() }
            let data = DocxExport.data(
                markdown: page.markdown,
                bibliographyMarkdown: page.bibliography,
                documentURL: page.documentURL
            )
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self.present(NSAlert(error: error))
            }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let url = saveURL(name: exportTitle, fileExtension: "pdf") else {
            return
        }
        let includeQR = EditorPreferences.printQRCode
        withExportPage(sharing: includeQR) { page in
            // No panel, so this run is not modal.
            if Handout.writePDF(self.makeHandout(page, includeQR: includeQR), to: url) { return }
            let alert = NSAlert()
            alert.messageText = "The PDF could not be written."
            alert.informativeText = "Check that the folder can be written to, then try again."
            self.present(alert)
        }
    }

    @objc func printPreview(_ sender: Any?) {
        let includeQR = EditorPreferences.printQRCode
        withExportPage(statusFirst: true, sharing: includeQR) { page in
            self.print(page, includeQR: includeQR)
        }
    }

    private func print(_ page: ExportPage, includeQR: Bool) {
        let view = makeHandout(page, includeQR: includeQR)
        if let printHookForTesting {
            printHookForTesting(view)
            return
        }
        let operation = NSPrintOperation(view: view, printInfo: Handout.printInfo())
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window, window.isVisible {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            afterMainQueueBlock { operation.run() }
        }
    }

    // MARK: - Formatting actions

    @objc func toggleBold(_ sender: Any?) {
        editor.toggleBold()
    }

    @objc func toggleItalic(_ sender: Any?) {
        editor.toggleItalic()
    }

    @objc func toggleInlineCode(_ sender: Any?) {
        editor.toggleInlineCode()
    }

    @objc func insertLink(_ sender: Any?) {
        editor.insertLink()
    }

    /// Calls `body` with the text for a share link. The main thread does not
    /// wait. A document with no citation keys gets its answer at once.
    private func withShareText(_ body: @escaping (CitationController.ShareText) -> Void) {
        citations.shareText(
            source: editor.source,
            documentURL: loomingsDocument?.citationDocumentURL,
            allowPaths: citationPathsAllowed,
            completion: body
        )
    }

    @objc func copyShareLink(_ sender: Any?) {
        withShareText { shared in
            do {
                let url = try ShareLink.url(
                    for: shared.source,
                    family: ThemeManager.shared.family,
                    mode: ThemeManager.shared.mode.rawValue
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                self.shareStatus = shared.failure ?? shared.styleNote
                if let status = self.shareStatus { self.markupOverlay.show(status) }
            } catch {
                self.present(NSAlert(error: error))
            }
        }
    }

    /// What the last Copy Share Link had to say.
    private(set) var shareStatus: String?

    func jump(to item: OutlineItem) {
        let length = editor.textView.textStorage?.length ?? 0
        let range = NSRange(location: min(item.range.location, length), length: 0)
        editor.textView.setSelectedRange(range)
        editor.textView.scrollRangeToVisible(range)
        window?.makeFirstResponder(editor.textView)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleBold(_:)),
             #selector(toggleItalic(_:)),
             #selector(toggleInlineCode(_:)),
             #selector(insertLink(_:)):
            // Not the preview, the References filter or a sheet's field: the
            // command edits the editor's text.
            return window?.firstResponder === editor.textView
        case #selector(sendWithAirDrop(_:)):
            menuItem.toolTip = airDropAvailable ? nil : "AirDrop is not available on this Mac right now."
            return airDropAvailable
        case #selector(setWriteMode(_:)):
            menuItem.state = viewMode == .write ? .on : .off
        case #selector(setSplitMode(_:)):
            menuItem.state = viewMode == .split ? .on : .off
        case #selector(setPreviewMode(_:)):
            menuItem.state = viewMode == .preview ? .on : .off
        case #selector(toggleProjectorMode(_:)):
            menuItem.state = isProjectorMode ? .on : .off
        case #selector(toggleWritingHistory(_:)):
            menuItem.state = history.isRecording ? .on : .off
            let saved = loomingsDocument?.fileURL != nil
            menuItem.toolTip = saved ? nil : "Save the document to record its history."
            return saved
        case #selector(replayWritingHistory(_:)), #selector(deleteWritingHistory(_:)):
            return history.hasHistory(fileURL: loomingsDocument?.fileURL)
        case #selector(chooseBundledStyle(_:)):
            let choices = currentChoices
            menuItem.state = choices != nil && choices?.style == menuItem.representedObject as? String ? .on : .off
            return window?.attachedSheet == nil
        case #selector(chooseStyleFile(_:)):
            let choices = currentChoices
            menuItem.state = choices != nil && choices?.style == nil ? .on : .off
            return window?.attachedSheet == nil
        case #selector(chooseLanguage(_:)):
            let choices = currentChoices
            menuItem.state = choices != nil && choices?.language == menuItem.representedObject as? String ? .on : .off
            return window?.attachedSheet == nil
        case #selector(chooseBibliography(_:)):
            return window?.attachedSheet == nil
        case #selector(toggleReferences(_:)):
            menuItem.state = isLibraryShown ? .on : .off
            return EditorPreferences.referencesEnabled
        case #selector(toggleSidebar(_:)):
            menuItem.state = sidebarShown && EditorPreferences.sidebarEnabled ? .on : .off
            return EditorPreferences.sidebarEnabled
        default:
            return true
        }
        return true
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "eu.tiagojacinto.loomings.toolbar.v2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [ToolbarItem.viewMode]
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Toolbar

    /// The mode switch is centred; the right holds tools the menus otherwise
    /// hide. New, Open and Save live in the File menu and on their shortcuts.
    private enum ToolbarItem {
        static let viewMode = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.viewMode")
        static let outline = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.outline")
        static let theme = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.theme")
        static let share = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.share")
        static let files = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.files")
    }

    private var modeSwitch: ModeSwitch?
    private var toolButtons: [ToolbarIconButton] = []
    private var shareButton: ToolbarIconButton?
    private var outlineButton: ToolbarIconButton?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            ToolbarItem.viewMode,
            .flexibleSpace,
            ToolbarItem.outline,
            ToolbarItem.theme,
            ToolbarItem.share,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isBordered = false

        switch itemIdentifier {
        case ToolbarItem.viewMode:
            let control = ModeSwitch(labels: ["Write", "Split", "Preview"])
            control.selectedIndex = viewMode.rawValue
            control.onSelect = { [weak self] index in
                self?.setViewMode(ViewMode(rawValue: index) ?? .write)
            }
            control.applyPalette(ThemeManager.shared.resolved())
            modeSwitch = control
            item.label = "View"
            item.view = control

        case ToolbarItem.files:
            item.label = "Files"
            item.view = makeTool(symbol: "sidebar.left", label: "Show or Hide Files", action: #selector(toggleSidebar(_:)))

        case ToolbarItem.outline:
            item.label = "Outline"
            let button = makeTool(symbol: "list.bullet.indent", label: "Go to Heading", action: #selector(showOutlineMenu(_:)))
            outlineButton = button
            item.view = button

        case ToolbarItem.theme:
            item.label = "Theme"
            item.view = makeTool(symbol: "circle.lefthalf.filled", label: "Theme", action: #selector(showThemeMenu(_:)))

        case ToolbarItem.share:
            item.label = "Share"
            let button = makeTool(symbol: "link", label: "Share", action: #selector(showShareMenu(_:)))
            shareButton = button
            item.view = button

        default:
            return nil
        }

        return item
    }

    /// The Files button is in the title bar only while the feature is on.
    private func syncFilesToolbarItem() {
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == ToolbarItem.files }
        if EditorPreferences.sidebarEnabled, index == nil {
            toolbar.insertItem(withItemIdentifier: ToolbarItem.files, at: 0)
        } else if !EditorPreferences.sidebarEnabled, let index {
            toolbar.removeItem(at: index)
        }
    }

    private func makeTool(symbol: String, label: String, action: Selector) -> ToolbarIconButton {
        let button = ToolbarIconButton(symbol: symbol, label: label)
        button.target = self
        button.action = action
        button.applyPalette(ThemeManager.shared.resolved())
        toolButtons.append(button)
        return button
    }

    private func applyToolbarPalette(_ resolved: ResolvedPalette?) {
        modeSwitch?.applyPalette(resolved)
        columnTabs.applyPalette(resolved)
        for button in toolButtons {
            button.applyPalette(resolved)
        }
    }

    @objc private func showOutlineMenu(_ sender: NSButton) {
        popUpOutline(from: sender)
    }

    /// View > Go to Heading: the same list as the toolbar tool.
    @objc func goToHeading(_ sender: Any?) {
        popUpOutline(from: outlineButton ?? statusBar)
    }

    private func popUpOutline(from anchor: NSView) {
        let menu = NSMenu(title: "Go to Heading")
        let entries = outlineEntries()
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No Headings", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for entry in entries {
            let heading = entry.item
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(jumpToOutlineItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = heading.range.location
            item.indentationLevel = min(4, max(0, heading.level - 1))
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
    }

    /// The item's tag is its heading's source location.
    @objc private func jumpToOutlineItem(_ sender: NSMenuItem) {
        guard let heading = editor.outline.first(where: { $0.range.location == sender.tag }) else { return }
        jump(to: heading)
    }

    @objc private func showThemeMenu(_ sender: NSButton) {
        guard let themeMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Theme" })?.submenu,
              let menu = themeMenu.copy() as? NSMenu else {
            return
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func copyShareLinkFromToolbar(_ sender: Any?) {
        copyShareLink(sender)
        shareButton?.confirm()
    }

    // MARK: - Share menu

    private func makeShareMenu() -> NSMenu {
        let menu = NSMenu(title: "Share")
        let copy = NSMenuItem(title: "Copy Share Link", action: #selector(copyShareLinkFromToolbar(_:)), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        let qr = NSMenuItem(title: "Show QR Code\u{2026}", action: #selector(showQRCode(_:)), keyEquivalent: "")
        qr.target = self
        menu.addItem(qr)
        let airDrop = NSMenuItem(title: "Send with AirDrop\u{2026}", action: #selector(sendWithAirDrop(_:)), keyEquivalent: "")
        airDrop.target = self
        airDrop.isEnabled = airDropAvailable
        if !airDropAvailable { airDrop.toolTip = "AirDrop is not available on this Mac right now." }
        menu.addItem(airDrop)
        menu.autoenablesItems = false
        return menu
    }

    // MARK: - AirDrop

    private var sentFiles: [URL] = []

    private var airDropAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: [URL(fileURLWithPath: "/tmp/x.md")]) ?? false
    }

    /// The current text, saved or not, as a Markdown file named after the
    /// document. Removed when the window closes.
    private func fileToSend() -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Loomings Send", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = exportTitle.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(name.isEmpty ? "Untitled" : name).appendingPathExtension("md")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(editor.source.utf8).write(to: url, options: .atomic)
            sentFiles.append(folder)
            return url
        } catch {
            return nil
        }
    }

    @objc func sendWithAirDrop(_ sender: Any?) {
        guard let service = NSSharingService(named: .sendViaAirDrop), let url = fileToSend() else { return }
        service.perform(withItems: [url])
    }

    private func removeSentFiles() {
        for folder in sentFiles { try? FileManager.default.removeItem(at: folder) }
        sentFiles = []
    }

    func airDropFileForTesting() -> URL? { fileToSend() }
    var airDropAvailableForTesting: Bool { airDropAvailable }

    @objc private func showShareMenu(_ sender: NSButton) {
        makeShareMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// The share link as a QR code to show a room, or why there is none.
    private func qrContent(for source: String) -> (image: NSImage?, caption: String) {
        let manager = ThemeManager.shared
        guard let url = try? ShareLink.url(for: source, family: manager.family, mode: manager.mode.rawValue),
              let code = ShareQRCode.image(for: url, side: 720) else {
            return (nil, "This document is too long for a QR code; share it as a link.")
        }
        return (NSImage(cgImage: code, size: NSSize(width: 240, height: 240)), "Scan to open this document in Loomings.")
    }

    @objc func showQRCode(_ sender: Any?) {
        withShareText { shared in
            if let failure = shared.failure { self.markupOverlay.show(failure) }
            self.showQRCode(for: shared.source)
        }
    }

    private func showQRCode(for source: String) {
        qrSourceForTesting = source
        let content = qrContent(for: source)
        var rows: [NSView] = []
        if let image = content.image {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.widthAnchor.constraint(equalToConstant: 240).isActive = true
            view.heightAnchor.constraint(equalToConstant: 240).isActive = true
            view.setAccessibilityLabel("QR code of the share link")
            rows.append(view)
        }
        rows.append(TeachingPopovers.label(content.caption, secondary: content.image == nil))
        let anchor: NSView = shareButton ?? statusBar
        TeachingPopovers.show(TeachingPopovers.column(rows), relativeTo: anchor.bounds, of: anchor, palette: ThemeManager.shared.resolved())
    }

    var shareMenuTitlesForTesting: [String] { makeShareMenu().items.map(\.title) }
    var qrCaptionForTesting: String? { qrContent(for: editor.source).caption }
    private(set) var qrSourceForTesting: String?
    func showQRCodeForTesting() { showQRCode(nil) }
}

/// Owns the preview renderer and its block cache. Only ever called on the
/// window's serial preview queue, so it needs no lock.
private final class PreviewPipeline: @unchecked Sendable {
    private let renderer = PreviewRenderer(producesHTML: false)
    private var palette: ResolvedPalette?
    private var bodySize: CGFloat = 0
    private var themed = false

    func render(
        source: String,
        documentURL: URL?,
        palette: ResolvedPalette?,
        theme: PreviewTheme
    ) -> PreviewDocument {
        // A new palette or type size (projector mode) is a new theme, which
        // clears the renderer's cached blocks.
        if !themed || self.palette != palette || bodySize != theme.bodyFont.pointSize {
            renderer.theme = theme
            self.palette = palette
            bodySize = theme.bodyFont.pointSize
            themed = true
        }
        return renderer.render(source: source, documentURL: documentURL)
    }
}

/// The right column. Escape in the preview or on the control comes here.
final class RightColumnView: NSView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// A split view whose divider takes the palette's border role.
final class ThemedSplitView: NSSplitView {
    var themedDividerColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override var dividerColor: NSColor {
        themedDividerColor ?? super.dividerColor
    }

    /// With one pane hidden there is nothing to divide; no line at the edge.
    override var dividerThickness: CGFloat {
        arrangedSubviews.contains(where: \.isHidden) ? 0 : super.dividerThickness
    }
}

/// The newest preview generation, readable from the preview queue.
private final class PreviewTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var latest = 0

    func set(_ generation: Int) {
        lock.lock(); latest = generation; lock.unlock()
    }

    private var begun = 0

    /// Whether `generation` is the newest. A render that is will run, and is
    /// counted.
    func start(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard latest == generation else { return false }
        begun += 1
        return true
    }

    /// How many renders have started.
    var started: Int {
        lock.lock(); defer { lock.unlock() }
        return begun
    }
}
