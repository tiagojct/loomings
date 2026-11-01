import AppKit
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
    NSMenuItemValidation
{
    let editor = EditorController()
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
    private let splitView = ThemedSplitView()
    private let statusBar = StatusBarView()
    private var statusHeightConstraint: NSLayoutConstraint!
    private var lineRuler: LineNumberRulerView!
    private var statusWorkItem: DispatchWorkItem?
    private var previewWorkItem: DispatchWorkItem?
    private(set) var viewMode: ViewMode = .write
    private var syncSource: String?
    private var syncUntil = Date.distantPast
    private var previewGeneration = 0
    private let previewPipeline = PreviewPipeline()
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
        window.tabbingMode = .preferred
        window.isRestorable = false
        window.center()

        super.init(window: window)

        window.title = document.displayName
        window.windowController = self
        window.delegate = self

        configureContent()
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

        document.editor = editor
        editor.setText(document.pendingText)
        applyPreferences()
        applyViewMode()
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
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(previewScrollView)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
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

        window.contentView = containerView

        scrollView.hasVerticalRuler = true
        lineRuler = LineNumberRulerView(scrollView: scrollView, editor: editor)
        scrollView.verticalRulerView = lineRuler
        scrollView.rulersVisible = EditorPreferences.showLineNumbers
    }

    private func wireEditorCallbacks() {
        editor.onEdit = { [weak self] in
            guard let self else { return }
            // Notes rest while the writer types and come back with the parse.
            self.editor.textView.setDecorations([], for: "notes")
            self.schedulePreviewUpdate()
        }
        editor.onAnalysis = { [weak self] _ in
            guard let self else { return }
            self.applyTeachingReport()
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
        editor.companionAnalysis = { source in TeachingReport.make(source: source) }
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

    private func applyTeachingReport() {
        let issues = currentReport?.lintIssues ?? []
        let tint = ThemeManager.shared.resolved()?.colors.accentColor ?? .systemOrange
        editor.textView.setDecorations(
            issues.map { EditorDecoration(range: $0.range, style: .squiggle(tint)) },
            for: "notes"
        )
        statusBar.setNotes(count: issues.count)
    }

    private func lineNumber(of issue: LintIssue) -> Int {
        editor.lineNumber(at: issue.range.location)
    }

    private func showNotes(_ only: [LintIssue]? = nil) {
        guard let issues = only ?? currentReport?.lintIssues, !issues.isEmpty else { return }
        let content = TeachingPopovers.notes(
            issues,
            line: { [weak self] in self?.lineNumber(of: $0) ?? 1 },
            onFix: { [weak self] in self?.apply(fixOf: $0) },
            onGo: { [weak self] in self?.reveal($0.range) }
        )
        if let only, let first = only.first,
           let rect = editor.textView.segmentFrames(for: first.range).first {
            TeachingPopovers.show(content, relativeTo: rect, of: editor.textView, palette: ThemeManager.shared.resolved())
        } else {
            TeachingPopovers.show(content, relativeTo: statusBar.bounds, of: statusBar, palette: ThemeManager.shared.resolved())
        }
    }

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
        if let issue = currentReport?.lintIssues.first(where: { NSLocationInRange(location, $0.range) || NSMaxRange($0.range) == location }) {
            showNotes([issue])
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

    // MARK: - Paired lines

    /// Split view only: the source under the pointer lights its preview block.
    private func pair(editorLocation location: Int?) {
        guard viewMode == .split, let location else {
            previewTextView.highlightedBlockIndex = nil
            return
        }
        previewTextView.highlightedBlockIndex = PreviewDocument.blockIndex(
            in: previewTextView.blocks,
            containing: location
        )
    }

    /// Split view only: the preview block under the pointer lights its source.
    private func pair(previewBlock block: PreviewBlock?) {
        guard viewMode == .split else {
            editor.pairedRange = nil
            return
        }
        editor.pairedRange = block?.sourceRange
    }

    private func clearPairing() {
        previewTextView.highlightedBlockIndex = nil
        editor.pairedRange = nil
    }

    func pairForTesting(editorLocation location: Int) { pair(editorLocation: location) }
    func pairForTesting(previewBlockAt index: Int) {
        pair(previewBlock: previewTextView.blocks.indices.contains(index) ? previewTextView.blocks[index] : nil)
    }
    var previewHighlightedBlockKind: String? {
        previewTextView.highlightedBlockIndex.map { previewTextView.blocks[$0].kind.rawValue }
    }
    var editorPairedRange: NSRange? { editor.pairedRange }

    /// Lights both sides of one pair at once, for design snapshots.
    func pairBothForSnapshot(editorLocation location: Int) {
        pair(editorLocation: location)
        if let index = previewTextView.highlightedBlockIndex {
            editor.pairedRange = previewTextView.blocks[index].sourceRange
        }
    }

    private func applyViewMode() {
        clearPairing()
        let showEditor = viewMode != .preview
        let showPreview = viewMode != .write

        scrollView.isHidden = !showEditor
        previewScrollView.isHidden = !showPreview
        modeSwitch?.selectedIndex = viewMode.rawValue
        splitView.adjustSubviews()

        if showPreview {
            refreshPreview()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.viewMode == .split {
                    self.splitView.setPosition(self.splitView.bounds.width / 2, ofDividerAt: 0)
                }
                self.splitView.layoutSubtreeIfNeeded()
                self.applyColumnWidth()
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
        let measure = EditorPreferences.columnWidth.maxWidth * 0.9
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
        guard viewMode != .write else { return }
        previewWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshPreview()
        }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func refreshPreview() {
        guard viewMode != .write else { return }
        previewGeneration += 1
        let generation = previewGeneration
        let source = editor.source
        let documentURL = loomingsDocument?.fileURL
        let resolved = ThemeManager.shared.resolved()
        let theme = resolved.map { PreviewTheme.themed($0) } ?? .standard

        let pipeline = previewPipeline
        previewQueue.async { [weak self] in
            let rendered = pipeline.render(
                source: source,
                documentURL: documentURL,
                palette: resolved,
                theme: theme
            )
            DispatchQueue.main.async {
                guard let self,
                      generation == self.previewGeneration,
                      self.viewMode != .write else {
                    return
                }
                self.previewTextView.render(rendered, documentURL: documentURL)
            }
        }
    }

    private func syncPreviewToEditor() {
        guard viewMode == .split, !isLocked(by: "preview") else { return }
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
        guard viewMode == .split, !isLocked(by: "editor") else { return }
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
        editor.setFontSize(EditorPreferences.fontSize)
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
        previewTextView.applyTheme(resolved.map { PreviewTheme.themed($0) } ?? .standard)
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
        let visible = EditorPreferences.showStats
        statusBar.isHidden = !visible
        statusHeightConstraint?.constant = visible ? 24 : 0
        scheduleStatusUpdate()
    }

    private func applyLineNumbersVisibility() {
        scrollView.rulersVisible = EditorPreferences.showLineNumbers
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

        let maximum = EditorPreferences.columnWidth.maxWidth
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

    func renderedHTMLForTesting() -> String {
        let rendered = PreviewRenderer().render(
            source: editor.source,
            documentURL: loomingsDocument?.fileURL
        )
        return PreviewHTMLExport.document(
            title: exportTitle,
            bodyHTML: rendered.html,
            palette: ThemeManager.shared.resolved()
        )
    }

    func renderedPDFForTesting() -> Data {
        let view = makePrintablePreview(width: 612)
        return view.dataWithPDF(inside: view.bounds)
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

    private var exportTitle: String {
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
        let rendered = PreviewRenderer().render(
            source: editor.source,
            documentURL: loomingsDocument?.fileURL
        )
        let html = PreviewHTMLExport.document(
            title: exportTitle,
            bodyHTML: rendered.html,
            palette: ThemeManager.shared.resolved()
        )
        do {
            try html.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let url = saveURL(name: exportTitle, fileExtension: "pdf") else {
            return
        }
        let view = makePrintablePreview(width: 612)
        let data = view.dataWithPDF(inside: view.bounds)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func printPreview(_ sender: Any?) {
        let view = makePrintablePreview(width: 612)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    private func makePrintablePreview(width: CGFloat) -> NSTextView {
        let rendered = PreviewRenderer().render(
            source: editor.source,
            documentURL: loomingsDocument?.fileURL
        )
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = true
        view.backgroundColor = .white
        view.appearance = NSAppearance(named: .aqua)
        view.textContainerInset = NSSize(width: 36, height: 36)
        view.textStorage?.setAttributedString(rendered.attributed)

        if let container = view.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: width - 72,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let used = view.layoutManager?.usedRect(for: view.textContainer!).height ?? 0
        view.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(200, used + 72)
        )
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        return view
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

    @objc func copyShareLink(_ sender: Any?) {
        do {
            let url = try ShareLink.url(
                for: editor.source,
                family: ThemeManager.shared.family,
                mode: ThemeManager.shared.mode.rawValue
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

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
            return window?.firstResponder is NSTextView
        case #selector(setWriteMode(_:)):
            menuItem.state = viewMode == .write ? .on : .off
        case #selector(setSplitMode(_:)):
            menuItem.state = viewMode == .split ? .on : .off
        case #selector(setPreviewMode(_:)):
            menuItem.state = viewMode == .preview ? .on : .off
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
    }

    private var modeSwitch: ModeSwitch?
    private var toolButtons: [ToolbarIconButton] = []
    private var shareButton: ToolbarIconButton?

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

        case ToolbarItem.outline:
            item.label = "Outline"
            item.view = makeTool(symbol: "list.bullet.indent", label: "Go to Heading", action: #selector(showOutlineMenu(_:)))

        case ToolbarItem.theme:
            item.label = "Theme"
            item.view = makeTool(symbol: "circle.lefthalf.filled", label: "Theme", action: #selector(showThemeMenu(_:)))

        case ToolbarItem.share:
            item.label = "Share"
            let button = makeTool(symbol: "link", label: "Copy Share Link", action: #selector(copyShareLinkFromToolbar(_:)))
            shareButton = button
            item.view = button

        default:
            return nil
        }

        return item
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
        for button in toolButtons {
            button.applyPalette(resolved)
        }
    }

    @objc private func showOutlineMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "Go to Heading")
        let headings = editor.outline
        if headings.isEmpty {
            let empty = NSMenuItem(title: "No Headings", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, heading) in headings.enumerated() {
            let item = NSMenuItem(
                title: heading.title.isEmpty ? "(empty heading)" : heading.title,
                action: #selector(jumpToOutlineItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.indentationLevel = min(4, max(0, heading.level - 1))
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func jumpToOutlineItem(_ sender: NSMenuItem) {
        guard editor.outline.indices.contains(sender.tag) else { return }
        jump(to: editor.outline[sender.tag])
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
}

/// Owns the preview renderer and its block cache. Only ever called on the
/// window's serial preview queue, so it needs no lock.
private final class PreviewPipeline: @unchecked Sendable {
    private let renderer = PreviewRenderer(producesHTML: false)
    private var palette: ResolvedPalette?
    private var themed = false

    func render(
        source: String,
        documentURL: URL?,
        palette: ResolvedPalette?,
        theme: PreviewTheme
    ) -> PreviewDocument {
        // A new theme clears the renderer's cached blocks.
        if !themed || self.palette != palette {
            renderer.theme = theme
            self.palette = palette
            themed = true
        }
        return renderer.render(source: source, documentURL: documentURL)
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
