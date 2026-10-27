import AppKit
import LoomingsPreview

@MainActor
final class PreviewTextView: NSTextView, NSTextViewDelegate {
    var onScroll: (() -> Void)?

    private var blocks: [PreviewBlock] = []
    private var blockRanges: [NSRange] = []
    private var documentURL: URL?
    private var imageCache: [String: NSImage] = [:]
    private var imageTasks: Set<String> = []
    private var scrollObserver: NSObjectProtocol?
    private let renderer = PreviewRenderer()

    convenience init() {
        self.init(frame: .zero, textContainer: nil)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        if let container {
            super.init(frame: frameRect, textContainer: container)
        } else {
            let storage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            storage.addLayoutManager(layoutManager)
            let made = NSTextContainer(
                size: NSSize(width: frameRect.width, height: CGFloat.greatestFiniteMagnitude)
            )
            made.widthTracksTextView = true
            layoutManager.addTextContainer(made)
            super.init(frame: frameRect, textContainer: made)
        }
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: 24, height: 24)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = .zero
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        autoresizingMask = [.width]
        usesFindBar = false
        isAutomaticLinkDetectionEnabled = false
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        setAccessibilityLabel("Document preview")
        delegate = self

        if let container = textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func applyTheme(_ theme: PreviewTheme) {
        renderer.theme = theme
        backgroundColor = theme.background
        textColor = theme.textColor
        insertionPointColor = theme.linkColor
        selectedTextAttributes = [.backgroundColor: theme.quoteBorderColor.withAlphaComponent(0.25)]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewTextView is created in code")
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    // MARK: - Rendering

    func render(source: String, documentURL: URL?) {
        let rendered = renderer.render(source: source, documentURL: documentURL)
        render(rendered, documentURL: documentURL)
    }

    func render(_ rendered: PreviewDocument, documentURL: URL?) {
        let previousDocumentURL = self.documentURL
        self.documentURL = documentURL

        let topLine = topSourceLine()
        let previous = blocks
        let previousRanges = blockRanges
        let next = rendered.blocks

        var prefix = 0
        while prefix < min(previous.count, next.count),
              same(previous[prefix], next[prefix]) {
            prefix += 1
        }

        var suffix = 0
        while suffix < min(previous.count - prefix, next.count - prefix),
              same(previous[previous.count - 1 - suffix], next[next.count - 1 - suffix]) {
            suffix += 1
        }

        guard let storage = textStorage else { return }
        storage.beginEditing()

        let documentChanged = previousDocumentURL != documentURL
        if previous.isEmpty || documentChanged || (prefix == 0 && suffix == 0) {
            storage.setAttributedString(rendered.attributed)
        } else {
            // prefix can equal previous.count when every old block is also a
            // prefix of the new document (including an identical render, or a
            // pure append). Indexing previousRanges[prefix] would then be out
            // of bounds, which was the writing crash.
            let oldStart: Int
            if prefix < previousRanges.count {
                oldStart = previousRanges[prefix].location
            } else if let last = previousRanges.last {
                oldStart = last.location + last.length
            } else {
                oldStart = 0
            }

            let oldLast = previous.count - suffix - 1
            let oldEnd: Int
            if oldLast >= prefix, previousRanges.indices.contains(oldLast) {
                let range = previousRanges[oldLast]
                oldEnd = range.location + range.length
            } else {
                oldEnd = oldStart
            }

            let replacement = NSMutableAttributedString()
            let newLast = next.count - suffix
            if prefix < newLast, next.indices.contains(prefix), newLast <= next.count {
                for block in next[prefix..<newLast] {
                    replacement.append(block.attributed)
                }
            }
            if oldEnd >= oldStart {
                storage.replaceCharacters(
                    in: NSRange(location: oldStart, length: oldEnd - oldStart),
                    with: replacement
                )
            }
        }

        storage.endEditing()

        blocks = next
        recomputeRanges()
        loadImages()
        resizeToFit()
        restoreScroll(to: topLine)
        needsDisplay = true
    }

    func resizeToFit() {
        guard let layoutManager, let container = textContainer,
              let scrollView = enclosingScrollView else {
            return
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        let height = max(
            used + textContainerInset.height * 2,
            scrollView.contentSize.height
        )
        guard abs(frame.height - height) > 0.5 else { return }
        setFrameSize(NSSize(width: frame.width, height: height))
    }

    private func same(_ left: PreviewBlock, _ right: PreviewBlock) -> Bool {
        left.kind == right.kind && left.html == right.html
            && left.sourceLine == right.sourceLine
            && left.attributed.isEqual(to: right.attributed)
    }

    private func recomputeRanges() {
        blockRanges = []
        blockRanges.reserveCapacity(blocks.count)
        var location = 0
        for block in blocks {
            blockRanges.append(NSRange(location: location, length: block.attributed.length))
            location += block.attributed.length
        }
    }

    // MARK: - Scroll mapping

    func topSourceLine() -> Double? {
        guard !blocks.isEmpty,
              let layoutManager,
              let container = textContainer,
              let scrollView = enclosingScrollView else {
            return nil
        }

        let top = scrollView.contentView.bounds.minY
        let point = NSPoint(x: 0, y: top + textContainerInset.height)
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)

        guard let index = blockIndex(containing: character),
              let block = blocks[safe: index],
              blockRanges.indices.contains(index) else {
            return Double(blocks.first?.sourceLine ?? 0)
        }

        let range = blockRanges[index]
        let blockTop = layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(
                forCharacterRange: NSRange(location: range.location, length: 1),
                actualCharacterRange: nil
            ),
            in: container
        ).minY
        let blockHeight = max(1, blockHeight(at: index))
        let fraction = min(1, max(0, (top + textContainerInset.height - blockTop) / blockHeight))
        let nextLine = blocks[safe: index + 1]?.sourceLine ?? (block.sourceLine + 1)
        let span = Double(max(1, nextLine - block.sourceLine))
        return Double(block.sourceLine) + fraction * span
    }

    func scroll(toSourceLine line: Double) {
        guard !blocks.isEmpty else { return }
        let target = max(0, line)
        var best = 0
        for (index, block) in blocks.enumerated() {
            if Double(block.sourceLine) <= target { best = index } else { break }
        }

        guard blockRanges.indices.contains(best),
              let layoutManager,
              let container = textContainer,
              let scrollView = enclosingScrollView else {
            return
        }

        let range = blockRanges[best]
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: range.location, length: 1),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        let maximum = max(0, bounds.height - scrollView.contentView.bounds.height)
        let y = min(max(0, rect.minY - textContainerInset.height), maximum)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func observeScrolling(in scrollView: NSScrollView) {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onScroll?()
            }
        }
    }

    private func blockIndex(containing character: Int) -> Int? {
        guard !blockRanges.isEmpty else { return nil }
        var low = 0
        var high = blockRanges.count
        while low < high {
            let mid = (low + high) / 2
            let range = blockRanges[mid]
            if range.location + range.length <= character {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low < blockRanges.count ? low : blockRanges.count - 1
    }

    private func blockHeight(at index: Int) -> CGFloat {
        guard let layoutManager, let container = textContainer,
              blockRanges.indices.contains(index) else {
            return 1
        }
        let range = blockRanges[index]
        guard range.length > 0 else { return 1 }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).height
    }

    private func restoreScroll(to line: Double?) {
        guard let line else { return }
        DispatchQueue.main.async { [weak self] in
            self?.scroll(toSourceLine: line)
        }
    }

    // MARK: - Images

    private func loadImages() {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.loomingsImageURL, in: full) { [weak self] value, range, _ in
            guard let self, let raw = value as? String, !raw.isEmpty else { return }
            if let image = self.imageCache[raw] {
                self.applyImage(image, raw: raw)
                return
            }
            guard !self.imageTasks.contains(raw) else { return }
            self.imageTasks.insert(raw)

            let base = self.documentURL?.deletingLastPathComponent()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = PreviewTextView.loadImage(raw, baseURL: base)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.imageTasks.remove(raw)
                    if let image {
                        self.imageCache[raw] = image
                        self.applyImage(image, raw: raw)
                    } else {
                        self.applyMissingImage(raw: raw)
                    }
                }
            }
        }
    }

    nonisolated private static func loadImage(_ raw: String, baseURL: URL?) -> NSImage? {
        if raw.lowercased().hasPrefix("data:image/") {
            guard let comma = raw.firstIndex(of: ",") else { return nil }
            let encoded = String(raw[raw.index(after: comma)...])
            guard let data = Data(base64Encoded: encoded) else { return nil }
            return NSImage(data: data)
        }

        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }

        guard let baseURL else { return nil }
        let url = URL(fileURLWithPath: raw, relativeTo: baseURL).standardizedFileURL
        return NSImage(contentsOf: url)
    }

    private func applyImage(_ image: NSImage, raw: String) {
        guard let storage = textStorage else { return }
        let top = topSourceLine()
        let full = NSRange(location: 0, length: storage.length)
        var invalidated = false
        storage.enumerateAttribute(.loomingsImageURL, in: full) { value, range, _ in
            guard value as? String == raw,
                  let attachment = storage.attribute(
                      .attachment,
                      at: range.location,
                      effectiveRange: nil
                  ) as? NSTextAttachment else {
                return
            }
            let maximum: CGFloat = 620
            let size = image.size
            let scale = size.width > maximum ? maximum / size.width : 1
            attachment.bounds = NSRect(
                x: 0,
                y: -4,
                width: size.width * scale,
                height: size.height * scale
            )
            attachment.image = image
            invalidated = true
        }
        if invalidated {
            layoutManager?.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
            layoutManager?.invalidateDisplay(forCharacterRange: full)
            resizeToFit()
            restoreScroll(to: top)
            needsDisplay = true
        }
    }

    private func applyMissingImage(raw: String) {
        guard let storage = textStorage else { return }
        let top = topSourceLine()
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.loomingsImageURL, in: full) { value, range, _ in
            guard value as? String == raw,
                  let attachment = storage.attribute(
                      .attachment,
                      at: range.location,
                      effectiveRange: nil
                  ) as? NSTextAttachment else {
                return
            }
            let alt = storage.attribute(
                .loomingsImageAlt,
                at: range.location,
                effectiveRange: nil
            ) as? String ?? ""
            attachment.image = NSImage(
                systemSymbolName: "photo.badge.exclamationmark",
                accessibilityDescription: alt.isEmpty ? "Missing image" : alt
            )
        }
        layoutManager?.invalidateDisplay(forCharacterRange: full)
        resizeToFit()
        restoreScroll(to: top)
        needsDisplay = true
    }

    // MARK: - Links

    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        let url: URL?
        if let value = link as? URL {
            url = value
        } else if let value = link as? String {
            url = URL(string: value)
        } else {
            url = nil
        }
        guard let url else { return false }
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" || scheme == "mailto" {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
