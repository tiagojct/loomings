import AppKit
import Foundation
import LoomingsMarkdown
import LoomingsTheme

public struct EditorAnalysis: Sendable {
    public let outline: [OutlineItem]
    public let lineStarts: [Int]
    public let wordCount: Int
    public let characterCount: Int

    public init(
        outline: [OutlineItem],
        lineStarts: [Int],
        wordCount: Int,
        characterCount: Int
    ) {
        self.outline = outline
        self.lineStarts = lineStarts
        self.wordCount = wordCount
        self.characterCount = characterCount
    }

    public var lineCount: Int { lineStarts.count }

    public static let empty = EditorAnalysis(
        outline: [],
        lineStarts: [],
        wordCount: 0,
        characterCount: 0
    )
}

public struct SelectionStatistics: Sendable, Equatable {
    public let words: Int
    public let characters: Int
    public let lines: Int

    public init(words: Int, characters: Int, lines: Int) {
        self.words = words
        self.characters = characters
        self.lines = lines
    }
}

/// Owns a TextKit 2 text view and the background parse that feeds its
/// syntax styling.
///
/// The edit path only bumps a revision, cancels the pending debounce and
/// schedules work. Snapshotting and parsing happen after the keystroke has
/// returned; results are applied only when their revision is still current,
/// so a slow parse never blocks typing or overwrites newer text.
@MainActor
public final class EditorController: NSObject, NSTextViewDelegate {
    public let textView: EditorTextView

    /// Called after a user edit, never for programmatic `setText`.
    public var onEdit: (() -> Void)?
    public var onAnalysis: ((EditorAnalysis) -> Void)?
    public var onSelectionChange: (() -> Void)?
    public var onViewportChange: (() -> Void)?

    public private(set) var revision: UInt64 = 0
    /// Monotonic count of character edits, including undo and redo. Programmatic
    /// replacement via setText resets it to zero.
    public private(set) var editGeneration: UInt64 = 0
    public private(set) var lastAppliedRevision: UInt64 = 0
    public private(set) var lastEditHandlerNanoseconds: UInt64 = 0
    public private(set) var lastSnapshotNanoseconds: UInt64 = 0
    public private(set) var lastParseNanoseconds: UInt64 = 0
    /// Uptime (ns) at which the last applied background parse finished.
    public private(set) var lastParseFinishedAt: UInt64 = 0
    public private(set) var lastApplyNanoseconds: UInt64 = 0
    public private(set) var parseRequests: UInt64 = 0
    public private(set) var appliedParses: UInt64 = 0
    public private(set) var discardedParses: UInt64 = 0
    public private(set) var lastSpanCount = 0
    public private(set) var lastNodeCount = 0
    public private(set) var stylingApplies: UInt64 = 0
    public private(set) var analysis = EditorAnalysis.empty
    public private(set) var palette: ResolvedPalette?

    public private(set) var isFocusMode = false
    public private(set) var isTypewriterMode = false
    public private(set) var isSmartTypographyEnabled = true
    public private(set) var fontSize: CGFloat = 15
    public var outline: [OutlineItem] { analysis.outline }

    /// Source range lit because the pointer is over its preview block (Split
    /// view). Drawn by the text view; the text is never touched.
    public var pairedRange: NSRange? {
        didSet {
            guard pairedRange != oldValue else { return }
            textView.setDecorations(
                pairedRange.map { [EditorDecoration(range: $0, style: .lineFill(pairTint))] } ?? [],
                for: "pair"
            )
        }
    }

    private var pairTint: NSColor {
        (palette?.colors.selectionColor ?? .selectedTextBackgroundColor).withAlphaComponent(0.45)
    }

    /// Extra work run with every parse, on the same snapshot and off the main
    /// thread (the synchronous reparse runs it inline). Its result is stored
    /// in `companionResult` just before `onAnalysis`, and only for the current
    /// revision. The app uses it for the teaching checks.
    public var companionAnalysis: (@Sendable (String) -> any Sendable)?
    public private(set) var companionResult: (any Sendable)?

    /// Called with the character index of an option-click in the text.
    public var onOptionClick: ((Int) -> Void)? {
        didSet { textView.onOptionClick = onOptionClick }
    }

    /// Replaces `range` as an undoable edit, like typing would. Returns false
    /// when the range is outside the text or the edit is refused.
    @discardableResult
    public func replace(range: NSRange, with replacement: String) -> Bool {
        let length = (textView.string as NSString).length
        guard range.location >= 0, NSMaxRange(range) <= length,
              textView.shouldChangeText(in: range, replacementString: replacement) else { return false }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        return true
    }

    /// Parses again now, for example after the companion's inputs changed.
    public func reanalyze() {
        scheduleParse(after: 0)
    }

    /// The UTF-16 location under the pointer, or nil when it leaves the text.
    public var onPointerLocation: ((Int?) -> Void)?
    private var pointerTracker: PointerTracker?

    public var source: String { textView.string }

    private var spans: [MarkdownSyntaxSpan] = []
    private var styledRange = NSRange(location: 0, length: 0)
    private var parseWorkItem: DispatchWorkItem?
    private var parseToken: UInt64 = 0
    private var isApplyingProgrammaticChange = false
    private var pendingCharacterEdit = false
    private var stylingScheduled = false
    private var needsAttributeRefresh = true
    private var frontmatterRange: NSRange?
    private var scrollObservers: [NSObjectProtocol] = []

    private let parseQueue = DispatchQueue(
        label: "eu.tiagojacinto.loomings.parse",
        qos: .userInitiated
    )
    private let companionQueue = DispatchQueue(
        label: "eu.tiagojacinto.loomings.companion",
        qos: .userInitiated
    )

    /// Debounce before snapshotting and parsing. Scrolling restyles from the
    /// last parse immediately; this delay only guards the parser itself.
    private let parseDebounce: TimeInterval = 0.12

    public override init() {
        self.textView = EditorTextView(usingTextLayoutManager: true)
        super.init()
        configureTextView()
    }

    deinit {
        for observer in scrollObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        parseWorkItem?.cancel()
    }

    // MARK: - Public surface

    public func setText(_ text: String) {
        isApplyingProgrammaticChange = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.undoManager?.removeAllActions()
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        isApplyingProgrammaticChange = false
        pendingCharacterEdit = false

        spans = []
        frontmatterRange = nil
        needsAttributeRefresh = true
        styledRange = NSRange(location: 0, length: 0)

        if let palette {
            applyPalette(palette)
        }

        revision &+= 1
        editGeneration = 0
        lastAppliedRevision = 0
        analysis = .empty
        companionResult = nil
        onAnalysis?(analysis)
        scheduleParse(after: 0)
    }

    /// Restyle the viewport after the view gains a window or a size.
    public func requestVisibleStyling() {
        scheduleVisibleStyling()
    }

    /// Parses and applies on the calling thread. Tests use this to check the
    /// result without pumping a run loop; the editor never calls it.
    public func reparseSynchronously() {
        let revision = self.revision
        let start = DispatchTime.now().uptimeNanoseconds
        let output = MarkdownParser.parse(textView.string)
        lastParseNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let extra = companionAnalysis?(textView.string)

        guard revision == self.revision else {
            discardedParses &+= 1
            return
        }

        spans = output.spans
        appliedParses &+= 1
        lastAppliedRevision = revision
        lastSpanCount = output.spans.count
        lastNodeCount = output.nodeCount
        needsAttributeRefresh = true
        companionResult = extra
        applyFrontmatterAttribute(output.spans)
        applyAnalysis(output)
        applyVisibleStyling()
    }

    public func observeScrolling(in scrollView: NSScrollView) {
        for observer in scrollObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollObservers.removeAll()

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true

        let bounds = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleVisibleStyling()
                self?.onViewportChange?()
            }
        }
        let frame = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleVisibleStyling()
            }
        }
        scrollObservers = [bounds, frame]
    }

    public func visibleCharacterRange() -> NSRange {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else {
            return fallbackRange()
        }
        guard let viewport = layoutManager.textViewportLayoutController.viewportRange else {
            return fallbackRange()
        }

        let documentRange = contentManager.documentRange
        let start = contentManager.offset(from: documentRange.location, to: viewport.location)
        let end = contentManager.offset(from: documentRange.location, to: viewport.endLocation)
        guard end >= start, start >= 0 else { return fallbackRange() }
        return NSRange(location: start, length: end - start)
    }

    public static func editorFont(size: CGFloat = 15) -> NSFont {
        if let jetBrains = NSFont(name: "JetBrainsMono-Regular", size: size) {
            return jetBrains
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - NSTextViewDelegate

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // Spell checking and other attribute passes produce nil here. They
        // must not advance the parse revision.
        guard let replacementString else { return true }

        if isSmartTypographyEnabled,
           replacementString.count == 1,
           let character = replacementString.first,
           let storage = textView.textStorage,
           let smart = SmartTypography.replacement(
               for: character,
               at: affectedCharRange.location,
               in: storage.mutableString
           ) {
            textView.insertText(smart.text, replacementRange: smart.range)
            return false
        }

        pendingCharacterEdit = true
        return true
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return handleNewline()
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return handleIndent(outdent: false)
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return handleIndent(outdent: true)
        }
        return false
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        if isFocusMode {
            needsAttributeRefresh = true
        }
        scheduleVisibleStyling()
        onSelectionChange?()
        if isTypewriterMode {
            DispatchQueue.main.async { [weak self] in
                self?.centerCaretInViewport()
            }
        }
    }

    public func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticChange else { return }
        guard pendingCharacterEdit else { return }
        pendingCharacterEdit = false

        let start = DispatchTime.now().uptimeNanoseconds
        revision &+= 1
        editGeneration &+= 1
        needsAttributeRefresh = true
        parseWorkItem?.cancel()

        // Rendering attributes never mutate text, so a composition may be
        // styled while it is still being composed.
        scheduleParse(after: parseDebounce)
        lastEditHandlerNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        onEdit?()

        if isTypewriterMode {
            DispatchQueue.main.async { [weak self] in
                self?.centerCaretInViewport()
            }
        }
    }

    // MARK: - Line insertion and indentation

    public func handleNewline() -> Bool {
        guard textView.selectedRange().length == 0,
              let storage = textView.textStorage,
              storage.length > 0 else {
            return false
        }

        let text = storage.mutableString
        let location = min(textView.selectedRange().location, text.length)
        let probe = min(max(0, location), text.length - 1)
        let line = text.lineRange(for: NSRange(location: probe, length: 0))

        var contentEnd = min(line.location + line.length, text.length)
        while contentEnd > line.location, isNewline(text.character(at: contentEnd - 1)) {
            contentEnd -= 1
        }
        guard location == contentEnd else { return false }

        let lineText = text.substring(
            with: NSRange(location: line.location, length: contentEnd - line.location)
        )
        guard let continuation = MarkdownEditing.continuation(forLine: lineText) else {
            return false
        }

        if let replacement = continuation.replacementLine {
            textView.insertText(
                replacement,
                replacementRange: NSRange(
                    location: line.location,
                    length: contentEnd - line.location
                )
            )
            textView.setSelectedRange(NSRange(
                location: line.location + (replacement as NSString).length,
                length: 0
            ))
        } else if let insertion = continuation.insertion {
            textView.insertText(insertion, replacementRange: NSRange(location: location, length: 0))
        }
        return true
    }

    public func handleIndent(outdent: Bool) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else {
            return false
        }

        let text = storage.mutableString
        let selection = textView.selectedRange()
        let probe = min(max(0, selection.location), text.length - 1)
        let firstLine = text.lineRange(for: NSRange(location: probe, length: 0))
        let start = firstLine.location
        var end = firstLine.location + firstLine.length

        if selection.length > 0 {
            let selectedEnd = selection.location + selection.length
            let endProbe = min(max(0, selectedEnd), text.length - 1)
            let endLine = text.lineRange(for: NSRange(location: endProbe, length: 0))
            if selectedEnd == endLine.location, endLine.location > firstLine.location {
                end = endLine.location
            } else {
                end = endLine.location + endLine.length
            }
        }

        var blockEnd = min(end, text.length)
        while blockEnd > start, isNewline(text.character(at: blockEnd - 1)) {
            blockEnd -= 1
        }
        let block = text.substring(with: NSRange(location: start, length: blockEnd - start))
        let transformed = outdent
            ? MarkdownEditing.outdent(block)
            : MarkdownEditing.indent(block)
        guard transformed != block else { return true }

        textView.insertText(
            transformed,
            replacementRange: NSRange(location: start, length: blockEnd - start)
        )
        textView.setSelectedRange(NSRange(
            location: start,
            length: (transformed as NSString).length
        ))
        return true
    }

    private func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D
    }

    // MARK: - Parsing

    private func scheduleParse(after delay: TimeInterval) {
        parseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.beginParse()
        }
        parseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func beginParse() {
        let snapshotStart = DispatchTime.now().uptimeNanoseconds
        let source = textView.string
        let revision = self.revision
        lastSnapshotNanoseconds = DispatchTime.now().uptimeNanoseconds - snapshotStart

        parseRequests &+= 1
        parseToken &+= 1
        let token = parseToken

        let companion = companionAnalysis
        let companionBox = CompanionBox()
        let companionDone = DispatchGroup()
        if let companion {
            // Side by side with the parse, so it adds no waiting time.
            companionDone.enter()
            companionQueue.async {
                companionBox.value = companion(source)
                companionDone.leave()
            }
        }
        parseQueue.async { [weak self] in
            let parseStart = DispatchTime.now().uptimeNanoseconds
            let output = MarkdownParser.parse(source)
            let finished = DispatchTime.now().uptimeNanoseconds
            let duration = finished - parseStart
            companionDone.wait()
            let extra = companionBox.value

            DispatchQueue.main.async {
                guard let self else { return }
                self.lastParseFinishedAt = finished
                self.completeParse(
                    output,
                    extra: extra,
                    duration: duration,
                    revision: revision,
                    token: token
                )
            }
        }
    }

    private func completeParse(
        _ output: MarkdownParseOutput,
        extra: (any Sendable)?,
        duration: UInt64,
        revision: UInt64,
        token: UInt64
    ) {
        lastParseNanoseconds = duration
        lastSpanCount = output.spans.count
        lastNodeCount = output.nodeCount

        guard revision == self.revision, token == parseToken else {
            discardedParses &+= 1
            return
        }

        spans = output.spans
        appliedParses &+= 1
        lastAppliedRevision = revision
        needsAttributeRefresh = true
        companionResult = extra
        applyFrontmatterAttribute(output.spans)
        applyAnalysis(output)
        applyVisibleStyling()
    }

    private func applyFrontmatterAttribute(_ spans: [MarkdownSyntaxSpan]) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let next = spans.first { $0.kind == .frontmatter }?.range
        if let previous = frontmatterRange,
           previous != next,
           previous.location < storage.length {
            let clamped = intersection(previous, NSRange(location: 0, length: storage.length))
            if clamped.length > 0 {
                storage.addAttribute(
                    .foregroundColor,
                    value: palette?.colors.text ?? NSColor.labelColor,
                    range: clamped
                )
            }
        }
        if let next {
            let clamped = intersection(next, NSRange(location: 0, length: storage.length))
            if clamped.length > 0 {
                storage.addAttribute(
                    .foregroundColor,
                    value: palette?.colors.textGhost ?? NSColor.tertiaryLabelColor,
                    range: clamped
                )
            }
        }
        frontmatterRange = next
    }

    private func applyAnalysis(_ output: MarkdownParseOutput) {
        analysis = EditorAnalysis(
            outline: output.outline,
            lineStarts: output.lineStarts,
            wordCount: output.wordCount,
            characterCount: output.characterCount
        )
        onAnalysis?(analysis)
    }

    // MARK: - Editing commands

    @discardableResult
    public func toggleBold() -> Bool {
        wrapSelection(left: "**", right: "**")
    }

    @discardableResult
    public func toggleItalic() -> Bool {
        wrapSelection(left: "*", right: "*")
    }

    @discardableResult
    public func toggleInlineCode() -> Bool {
        wrapSelection(left: "`", right: "`")
    }

    @discardableResult
    public func wrapSelection(left: String, right: String) -> Bool {
        let selection = textView.selectedRange()
        if selection.length == 0 {
            let insertion = left + right
            textView.insertText(insertion, replacementRange: selection)
            textView.setSelectedRange(NSRange(
                location: selection.location + (left as NSString).length,
                length: 0
            ))
            return true
        }

        var text = selectedString()
        if left == "*", right == "*" {
            if text.hasPrefix("***"), text.hasSuffix("***"),
               (text as NSString).length >= 6 {
                text = String(text.dropFirst().dropLast())
                return replaceSelection(with: text)
            }
            if text.hasPrefix("**"), text.hasSuffix("**"),
               (text as NSString).length >= 4 {
                text = left + text + right
                return replaceSelection(with: text)
            }
        }

        if text.hasPrefix(left), text.hasSuffix(right),
           (text as NSString).length >= left.count + right.count {
            let inner = String(text.dropFirst(left.count).dropLast(right.count))
            return replaceSelection(with: inner)
        }
        return replaceSelection(with: left + text + right)
    }

    @discardableResult
    public func insertLink() -> Bool {
        let selection = textView.selectedRange()
        if selection.length == 0 {
            textView.insertText("[](url)", replacementRange: selection)
            textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return true
        }

        let label = selectedString()
        let insertion = "[\(label)](url)"
        textView.insertText(insertion, replacementRange: selection)
        let urlStart = selection.location + (label as NSString).length + 3
        textView.setSelectedRange(NSRange(location: urlStart, length: 3))
        return true
    }

    private func replaceSelection(with text: String) -> Bool {
        let selection = textView.selectedRange()
        textView.insertText(text, replacementRange: selection)
        textView.setSelectedRange(NSRange(
            location: selection.location,
            length: (text as NSString).length
        ))
        return true
    }

    private func selectedString() -> String {
        let selection = textView.selectedRange()
        guard selection.length > 0,
              let text = textView.textStorage?.mutableString else {
            return ""
        }
        return text.substring(with: selection)
    }

    // MARK: - Preferences and view behaviour

    public func applyPalette(_ resolved: ResolvedPalette?) {
        palette = resolved

        if let colors = resolved?.colors {
            textView.backgroundColor = colors.background
            textView.textColor = colors.text
            textView.insertionPointColor = colors.accentColor
            textView.selectedTextAttributes = [
                .backgroundColor: colors.selectionColor,
                .foregroundColor: colors.text,
            ]
            textView.typingAttributes[.foregroundColor] = colors.text
        } else {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
            textView.selectedTextAttributes = [:]
            textView.typingAttributes[.foregroundColor] = NSColor.labelColor
        }

        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(
                .foregroundColor,
                value: resolved?.colors.text ?? NSColor.labelColor,
                range: NSRange(location: 0, length: storage.length)
            )
        }
        applyFrontmatterAttribute(spans)
        if isFocusMode, let contentManager = textView.textLayoutManager?.textContentManager {
            let length = contentManager.offset(
                from: contentManager.documentRange.location,
                to: contentManager.documentRange.endLocation
            )
            applyFocusAttributes(to: NSRange(location: 0, length: length))
        }
        needsAttributeRefresh = true
        scheduleVisibleStyling()
    }

    public func setFontSize(_ size: CGFloat) {
        guard size != fontSize else { return }
        fontSize = size
        let font = Self.editorFont(size: size)
        textView.font = font
        textView.typingAttributes[.font] = font
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: storage.length)
            )
        }
        scheduleVisibleStyling()
    }

    public func setSmartTypography(_ enabled: Bool) {
        isSmartTypographyEnabled = enabled
    }

    public func setFocusMode(_ enabled: Bool) {
        isFocusMode = enabled
        needsAttributeRefresh = true
        if !enabled {
            clearFocusAttributes()
        }
        scheduleVisibleStyling()
    }

    /// Focus dimming is a transient text-storage colour override: TextKit's
    /// rendering attributes are only consulted when a fragment is laid out,
    /// so they cannot dim text that is already on screen after a toggle.
    private func applyFocusAttributes(to range: NSRange) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let visible = intersection(range, NSRange(location: 0, length: storage.length))
        guard visible.length > 0 else { return }

        let active = SentenceFocus.activeRange(
            in: storage.mutableString,
            caret: textView.selectedRange().location
        )
        let highlighted = intersection(active, visible)

        storage.beginEditing()
        storage.addAttribute(
            .foregroundColor,
            value: palette?.colors.textGhost ?? NSColor.tertiaryLabelColor,
            range: visible
        )
        if highlighted.length > 0 {
            storage.addAttribute(
                .foregroundColor,
                value: palette?.colors.text ?? NSColor.labelColor,
                range: highlighted
            )
        }
        storage.endEditing()
    }

    private func clearFocusAttributes() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(
            .foregroundColor,
            value: palette?.colors.text ?? NSColor.labelColor,
            range: NSRange(location: 0, length: storage.length)
        )
        storage.endEditing()
        applyFrontmatterAttribute(spans)
    }

    public func setTypewriterMode(_ enabled: Bool) {
        let changed = isTypewriterMode != enabled
        isTypewriterMode = enabled
        if enabled, changed {
            centerCaretInViewport()
        }
    }

    public func centerCaretInViewport() {
        guard let scrollView = textView.enclosingScrollView else { return }
        let caret = textView.selectedRange().location
        textView.scrollRangeToVisible(NSRange(location: caret, length: 0))

        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: caret, length: 0),
            actualRange: nil
        )
        guard screenRect != .zero, let window = textView.window else { return }

        let windowRect = window.convertFromScreen(screenRect)
        let local = textView.convert(windowRect, from: nil)
        let clipView = scrollView.contentView
        let target = local.midY - clipView.bounds.height / 2
        let maximum = max(0, textView.bounds.height - clipView.bounds.height)
        let y = min(max(0, target), maximum)

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Statistics

    public func lineNumber(at location: Int) -> Int {
        let starts = analysis.lineStarts
        guard !starts.isEmpty else { return 1 }
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(1, low)
    }

    public func scrollToLine(_ line: Int) {
        let starts = analysis.lineStarts
        guard !starts.isEmpty else { return }
        let index = min(max(0, line - 1), starts.count - 1)
        textView.scrollRangeToVisible(NSRange(location: starts[index], length: 0))
    }

    public func selectionStatistics() -> SelectionStatistics? {
        let selection = textView.selectedRange()
        guard selection.length > 0,
              let text = textView.textStorage?.mutableString else {
            return nil
        }

        let selected = text.substring(with: selection)
        let words = TextStatistics.countWords(selected)
        let startLine = lineNumber(at: selection.location)
        let end = selection.location + selection.length
        var endLine = lineNumber(at: end)

        if endLine > startLine, end < text.length {
            let endLineRange = text.lineRange(for: NSRange(location: end, length: 0))
            if end == endLineRange.location {
                endLine -= 1
            }
        }

        return SelectionStatistics(
            words: words,
            characters: selection.length,
            lines: max(1, endLine - startLine + 1)
        )
    }

    // MARK: - Styling

    private func scheduleVisibleStyling() {
        guard !stylingScheduled else { return }
        stylingScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stylingScheduled = false
            self.applyVisibleStyling()
        }
    }

    private func applyVisibleStyling() {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else {
            return
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let documentRange = contentManager.documentRange
        let length = contentManager.offset(
            from: documentRange.location,
            to: documentRange.endLocation
        )
        guard length > 0 else { return }

        let visible = visibleCharacterRange()
        let paddedStart = max(0, visible.location - 4096)
        let paddedEnd = min(length, visible.location + visible.length + 4096)
        guard paddedEnd > paddedStart else { return }
        let padded = NSRange(location: paddedStart, length: paddedEnd - paddedStart)

        if isFocusMode {
            applyFocusAttributes(to: padded)
        }
        if needsAttributeRefresh {
            needsAttributeRefresh = false
            if let textRange = makeTextRange(padded, contentManager: contentManager) {
                layoutManager.invalidateLayout(for: textRange)
                layoutManager.ensureLayout(for: textRange)
            }
            layoutManager.textViewportLayoutController.layoutViewport()
        }
        textView.needsDisplay = true

        styledRange = padded
        stylingApplies &+= 1
        lastApplyNanoseconds = DispatchTime.now().uptimeNanoseconds - start
    }

    /// Called by TextKit for each layout fragment. Rendering attributes must
    /// be supplied before a fragment is laid out; applying them afterwards
    /// leaves the already-drawn text unchanged.
    private func applyRenderingAttributes(
        layoutManager: NSTextLayoutManager,
        fragment: NSTextLayoutFragment
    ) {
        guard let contentManager = layoutManager.textContentManager else { return }
        let documentRange = contentManager.documentRange
        let start = contentManager.offset(
            from: documentRange.location,
            to: fragment.rangeInElement.location
        )
        let end = contentManager.offset(
            from: documentRange.location,
            to: fragment.rangeInElement.endLocation
        )
        guard end > start else { return }
        let range = NSRange(location: start, length: end - start)

        layoutManager.setRenderingAttributes([:], for: fragment.rangeInElement)


        let text = textView.textStorage?.mutableString ?? ""
        let focusRange: NSRange? = isFocusMode
            ? SentenceFocus.activeRange(
                in: text,
                caret: textView.selectedRange().location
            )
            : nil
        let active = focusRange.map { intersection($0, range) }
            ?? NSRange(location: 0, length: 0)
        let hasFocus = (focusRange?.length ?? 0) > 0
        guard !spans.isEmpty else { return }
        var index = firstSpanIndex(startingBefore: range.location + range.length)
        while index > 0 {
            let previous = spans[index - 1]
            if previous.range.location + previous.range.length > range.location {
                index -= 1
            } else {
                break
            }
        }

        while index < spans.count {
            let span = spans[index]
            if span.range.location >= range.location + range.length {
                break
            }
            let applyRange = hasFocus ? intersection(span.range, active) : span.range
            if applyRange.length > 0,
               intersection(applyRange, range).length > 0,
               let color = Self.color(for: span.kind),
               let textRange = makeTextRange(applyRange, contentManager: contentManager) {
                layoutManager.addRenderingAttribute(
                    .foregroundColor,
                    value: color,
                    for: textRange
                )
            }
            index += 1
        }
    }

    /// The syntax span at `location`, counting the position just past its
    /// last character (a click on a marker's right half lands there). A span
    /// that strictly contains the location wins over one that ends at it.
    public func span(at location: Int) -> MarkdownSyntaxSpan? {
        var index = firstSpanIndex(startingBefore: location + 1)
        var touching: MarkdownSyntaxSpan?
        while index > 0 {
            index -= 1
            let span = spans[index]
            let end = span.range.location + span.range.length
            if location >= span.range.location, location < end { return span }
            if location == end, touching == nil { touching = span }
            if end < location, span.kind != .frontmatter, span.kind != .codeBlockContent { break }
        }
        return touching
    }

    /// Starts reporting the character under the pointer through
    /// `onPointerLocation`. Idempotent.
    public func trackPointer() {
        guard pointerTracker == nil else { return }
        let tracker = PointerTracker(textView: textView) { [weak self] location in
            self?.onPointerLocation?(location)
        }
        pointerTracker = tracker
        textView.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: tracker
        ))
    }

    private func firstSpanIndex(startingBefore location: Int) -> Int {
        var low = 0
        var high = spans.count
        while low < high {
            let mid = (low + high) / 2
            if spans[mid].range.location < location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func makeTextRange(
        _ range: NSRange,
        contentManager: NSTextContentManager
    ) -> NSTextRange? {
        let documentRange = contentManager.documentRange
        guard let start = contentManager.location(
            documentRange.location,
            offsetBy: range.location
        ) else {
            return nil
        }
        guard let end = contentManager.location(start, offsetBy: range.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }

    private func fallbackRange() -> NSRange {
        let length = textView.textStorage?.length ?? 0
        let visibleLength = length <= 50_000 ? length : min(20_000, length)
        return NSRange(location: 0, length: visibleLength)
    }

    private func intersection(_ left: NSRange, _ right: NSRange) -> NSRange {
        let start = max(left.location, right.location)
        let end = min(left.location + left.length, right.location + right.length)
        return NSRange(location: start, length: max(0, end - start))
    }

    private func union(_ left: NSRange, _ right: NSRange) -> NSRange {
        guard left.length > 0 else { return right }
        guard right.length > 0 else { return left }
        let start = min(left.location, right.location)
        let end = max(left.location + left.length, right.location + right.length)
        return NSRange(location: start, length: end - start)
    }

    public static func color(for kind: MarkdownSyntaxKind) -> NSColor? {
        switch kind {
        case .frontmatter:
            return .tertiaryLabelColor
        default:
            return .secondaryLabelColor
        }
    }

    private func syntaxColor(for kind: MarkdownSyntaxKind) -> NSColor? {
        guard let colors = palette?.colors else {
            return Self.color(for: kind)
        }
        switch kind {
        case .headingMarker:
            return colors.headingColor
        case .emphasisMarker, .strongMarker, .strikethroughMarker:
            return colors.emphasisColor
        case .inlineCodeMarker, .fencedCodeDelimiter, .codeBlockContent:
            return colors.codeColor
        case .linkPunctuation, .imagePunctuation:
            return colors.linkColor
        case .blockQuoteMarker:
            return colors.textDim
        case .listMarker:
            return colors.markerColor
        case .thematicBreak, .rawHTML, .frontmatter:
            return colors.textGhost
        }
    }

    // MARK: - Configuration

    private func configureTextView() {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = Self.editorFont()
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.typingAttributes = [
            .font: Self.editorFont(),
            .foregroundColor: NSColor.labelColor,
        ]
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        if let container = textView.textLayoutManager?.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        textView.setAccessibilityLabel("Markdown document")
        textView.textLayoutManager?.renderingAttributesValidator = { [weak self] layoutManager, fragment in
            MainActor.assumeIsolated {
                self?.applyRenderingAttributes(
                    layoutManager: layoutManager,
                    fragment: fragment
                )
            }
        }
        textView.delegate = self
    }
}

/// Receives pointer events for the editor's text view and reports the
/// character under the pointer.
private final class PointerTracker: NSResponder {
    private weak var textView: NSTextView?
    private let report: (Int?) -> Void

    init(textView: NSTextView, report: @escaping (Int?) -> Void) {
        self.textView = textView
        self.report = report
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PointerTracker is created in code")
    }

    override func mouseMoved(with event: NSEvent) {
        guard let textView else { return }
        let point = textView.convert(event.locationInWindow, from: nil)
        report(textView.characterIndexForInsertion(at: point))
    }

    override func mouseExited(with event: NSEvent) {
        report(nil)
    }
}

/// Carries a companion result from its queue to the parse queue; the group
/// wait orders the write before the read.
private final class CompanionBox: @unchecked Sendable {
    var value: (any Sendable)?
}
