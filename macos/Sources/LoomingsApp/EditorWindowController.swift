import AppKit
import LoomingsEditor
import LoomingsMarkdown
import LoomingsPreview
import LoomingsShare
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
    private var viewModeControl: NSSegmentedControl?
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
        window.minSize = NSSize(width: 480, height: 320)
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
            self?.schedulePreviewUpdate()
        }
        editor.onAnalysis = { [weak self] _ in
            guard let self else { return }
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

    private func applyViewMode() {
        let showEditor = viewMode != .preview
        let showPreview = viewMode != .write

        scrollView.isHidden = !showEditor
        previewScrollView.isHidden = !showPreview
        viewModeControl?.selectedSegment = viewMode.rawValue
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
        splitView.themedDividerColor = resolved?.colors.borderColor
        statusBar.applyPalette(resolved)
        applyChrome(resolved)
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
    }

    private func applyColumnWidth() {
        guard let window, window.contentView != nil else { return }
        containerView.layoutSubtreeIfNeeded()

        let available = scrollView.contentView.frame.width > 0
            ? scrollView.contentView.frame.width
            : scrollView.contentSize.width
        guard available > 0 else { return }

        let maximum = EditorPreferences.columnWidth.maxWidth
        let inset = max(24, (available - maximum) / 2)
        let containerWidth = max(120, min(maximum, available - inset * 2))

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
        let toolbar = NSToolbar(identifier: "eu.tiagojacinto.loomings.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Toolbar

    private enum ToolbarItem {
        static let newDocument = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.new")
        static let openDocument = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.open")
        static let saveDocument = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.save")
        static let viewMode = NSToolbarItem.Identifier("eu.tiagojacinto.loomings.viewMode")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItem.newDocument,
            ToolbarItem.openDocument,
            ToolbarItem.saveDocument,
            .flexibleSpace,
            .space,
            ToolbarItem.viewMode,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItem.newDocument,
            ToolbarItem.openDocument,
            ToolbarItem.saveDocument,
            .flexibleSpace,
            ToolbarItem.viewMode,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isBordered = true

        switch itemIdentifier {
        case ToolbarItem.newDocument:
            item.label = "New"
            item.paletteLabel = "New Document"
            item.toolTip = "New Document"
            item.image = NSImage(
                systemSymbolName: "square.and.pencil",
                accessibilityDescription: "New Document"
            )
            item.action = #selector(AppDelegate.newDocument(_:))
            item.target = nil

        case ToolbarItem.openDocument:
            item.label = "Open"
            item.paletteLabel = "Open Document"
            item.toolTip = "Open Document"
            item.image = NSImage(
                systemSymbolName: "folder",
                accessibilityDescription: "Open Document"
            )
            item.action = #selector(NSDocumentController.openDocument(_:))
            item.target = nil

        case ToolbarItem.saveDocument:
            item.label = "Save"
            item.paletteLabel = "Save Document"
            item.toolTip = "Save Document"
            item.image = NSImage(
                systemSymbolName: "square.and.arrow.down",
                accessibilityDescription: "Save Document"
            )
            item.action = #selector(NSDocument.save(_:))
            item.target = nil

        case ToolbarItem.viewMode:
            let control = NSSegmentedControl(
                labels: ["Write", "Split", "Preview"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(changeViewMode(_:))
            )
            control.selectedSegment = viewMode.rawValue
            control.segmentStyle = .texturedRounded
            control.setAccessibilityLabel("View mode")
            viewModeControl = control
            item.label = "View"
            item.view = control

        default:
            return nil
        }

        return item
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
