import AppKit
import LoomingsEditor
import LoomingsTeaching
import LoomingsTheme

/// Two documents side by side, row by row: the other document on the left,
/// the front document on the right. Removed lines are tinted on the left,
/// added lines on the right, and inside a changed pair the changed words are
/// underlined. The two sides scroll together.
@MainActor
final class CompareWindowController: NSWindowController {
    private enum Kind { case same, changed, removed, added }
    private struct Row {
        let left: Substring?
        let right: Substring?
        let kind: Kind
    }

    private let leftView = EditorTextView(usingTextLayoutManager: true)
    private let rightView = EditorTextView(usingTextLayoutManager: true)
    private let header = NSTextField(labelWithString: "")
    private var syncing = false
    private var observers: [NSObjectProtocol] = []

    private(set) var changedLineCount = 0
    var headerText: String { header.stringValue }
    var leftText: String { leftView.string }
    var rightText: String { rightView.string }

    init(leftTitle: String, leftText: String, rightTitle: String, rightText: String, palette: ResolvedPalette?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(leftTitle) and \(rightTitle)"
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let rows = Self.rows(old: leftText, new: rightText)
        changedLineCount = rows.filter { $0.kind != .same }.count
        let lines = changedLineCount == 1 ? "1 line changed" : "\(changedLineCount) lines changed"
        header.stringValue = "Left: \(leftTitle)  \u{00B7}  Right: \(rightTitle)  \u{00B7}  \(lines)"
        build(rows: rows, palette: palette)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CompareWindowController is created in code")
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private static func rows(old: String, new: String) -> [Row] {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false)
        var rows: [Row] = []
        var removed: [Substring] = []
        var added: [Substring] = []
        func flush() {
            let paired = min(removed.count, added.count)
            for index in 0..<paired { rows.append(Row(left: removed[index], right: added[index], kind: .changed)) }
            for line in removed.dropFirst(paired) { rows.append(Row(left: line, right: nil, kind: .removed)) }
            for line in added.dropFirst(paired) { rows.append(Row(left: nil, right: line, kind: .added)) }
            removed = []
            added = []
        }
        for op in LineDiff.lines(old: a, new: b) {
            switch op {
            case .same(let x, _):
                flush()
                rows.append(Row(left: a[x], right: a[x], kind: .same))
            case .removed(let x): removed.append(a[x])
            case .added(let y): added.append(b[y])
            }
        }
        flush()
        return rows
    }

    private func build(rows: [Row], palette: ResolvedPalette?) {
        guard let window else { return }
        let colors = palette?.colors
        let font = NSFont(name: "JetBrainsMono-Regular", size: 14) ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
        let ink = colors?.text ?? .labelColor
        let removedTint = (colors?.accentColor ?? .systemRed).withAlphaComponent(0.18)
        let addedTint = (colors?.linkColor ?? .systemGreen).withAlphaComponent(0.18)

        let left = NSMutableAttributedString()
        let right = NSMutableAttributedString()
        var leftMarks: [EditorDecoration] = []
        var rightMarks: [EditorDecoration] = []
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]

        // A gutter sign says what a row is, so the meaning never rests on hue.
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors?.textDim ?? .secondaryLabelColor]
        let leftSign: (Kind) -> String = { $0 == .removed || $0 == .changed ? "\u{2212} " : "  " }
        let rightSign: (Kind) -> String = { $0 == .added || $0 == .changed ? "+ " : "  " }

        for (index, row) in rows.enumerated() {
            let ending = index == rows.count - 1 ? "" : "\n"
            let leftStart = left.length
            let rightStart = right.length
            left.append(NSAttributedString(string: row.left == nil ? "  " : leftSign(row.kind), attributes: dim))
            right.append(NSAttributedString(string: row.right == nil ? "  " : rightSign(row.kind), attributes: dim))
            let leftTextStart = left.length
            let rightTextStart = right.length
            left.append(NSAttributedString(string: String(row.left ?? "") + ending, attributes: base))
            right.append(NSAttributedString(string: String(row.right ?? "") + ending, attributes: base))
            let leftLine = NSRange(location: leftStart, length: 2 + (String(row.left ?? "") as NSString).length)
            let rightLine = NSRange(location: rightStart, length: 2 + (String(row.right ?? "") as NSString).length)
            switch row.kind {
            case .same:
                break
            case .removed:
                leftMarks.append(EditorDecoration(range: leftLine, style: .lineFill(removedTint)))
            case .added:
                rightMarks.append(EditorDecoration(range: rightLine, style: .lineFill(addedTint)))
            case .changed:
                leftMarks.append(EditorDecoration(range: leftLine, style: .lineFill(removedTint)))
                rightMarks.append(EditorDecoration(range: rightLine, style: .lineFill(addedTint)))
                if let old = row.left, let new = row.right {
                    let words = LineDiff.words(old: old, new: new)
                    for range in words.removed {
                        left.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: NSRange(range, in: old).shifted(by: leftTextStart))
                    }
                    for range in words.added {
                        right.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: NSRange(range, in: new).shifted(by: rightTextStart))
                    }
                }
            }
        }

        let background = colors?.background ?? .textBackgroundColor
        func pane(_ view: EditorTextView, _ text: NSAttributedString, _ marks: [EditorDecoration], label: String) -> NSScrollView {
            view.isEditable = false
            view.isSelectable = true
            view.isRichText = true
            view.drawsBackground = true
            view.backgroundColor = background
            view.textContainerInset = NSSize(width: 16, height: 16)
            // One row per line on both sides: no wrapping, so rows stay level.
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = true
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.autoresizingMask = []
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.textStorage?.setAttributedString(text)
            view.setDecorations(marks, for: "diff")
            view.setAccessibilityLabel(label)
            let scroll = NSScrollView()
            scroll.documentView = view
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = true
            scroll.backgroundColor = background
            scroll.contentView.postsBoundsChangedNotifications = true
            view.sizeToFit()
            view.frame.size.width = max(view.frame.width, 400)
            return scroll
        }
        let leftScroll = pane(leftView, left, leftMarks, label: "Left document")
        let rightScroll = pane(rightView, right, rightMarks, label: "Right document")
        sync(leftScroll, to: rightScroll)
        sync(rightScroll, to: leftScroll)

        header.font = .systemFont(ofSize: 12, weight: .medium)
        header.textColor = colors?.textDim ?? .secondaryLabelColor
        header.lineBreakMode = .byTruncatingMiddle
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(leftScroll)
        split.addArrangedSubview(rightScroll)
        let headerBar = NSStackView(views: [header])
        headerBar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        let stack = NSStackView(views: [headerBar, split])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            split.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.contentView = content
        window.backgroundColor = background
        DispatchQueue.main.async { split.setPosition(split.bounds.width / 2, ofDividerAt: 0) }
    }

    /// Rows line up, so scrolling one side by an offset scrolls the other by the same.
    private func sync(_ source: NSScrollView, to target: NSScrollView) {
        let observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: source.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.syncing else { return }
                self.syncing = true
                target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.origin.x, y: source.contentView.bounds.origin.y))
                target.reflectScrolledClipView(target.contentView)
                self.syncing = false
            }
        }
        observers.append(observer)
    }
}

private extension NSRange {
    func shifted(by offset: Int) -> NSRange { NSRange(location: location + offset, length: length) }
}
