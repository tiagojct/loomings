import AppKit
import LoomingsEditor
import LoomingsTheme

/// A vertical ruler that prints 1-based line numbers for the visible lines.
/// It reads line starts from the editor's parse result and asks the text view
/// for each line's position, so wrapping and insets are handled by TextKit.
@MainActor
final class LineNumberRulerView: NSRulerView {
    weak var editor: EditorController?
    var numberColor: NSColor = .tertiaryLabelColor

    private var boundsObserver: NSObjectProtocol?

    init(scrollView: NSScrollView, editor: EditorController) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor.textView
        ruleThickness = 44
        setAccessibilityElement(false)

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("LineNumberRulerView is created in code")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ rect: NSRect) {
        guard let editor,
              let layoutManager = editor.textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let scrollView else {
            return
        }

        let textView = editor.textView
        let visible = editor.visibleCharacterRange()
        guard visible.length > 0 else { return }
        let documentStart = contentManager.documentRange.location
        guard let start = contentManager.location(documentStart, offsetBy: visible.location),
              let end = contentManager.location(start, offsetBy: visible.length) else {
            return
        }

        let clipY = scrollView.contentView.bounds.origin.y
        let inset = textView.textContainerInset.height
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: numberColor,
        ]

        var lastNumber = -1
        layoutManager.enumerateTextLayoutFragments(
            from: start,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentStart = contentManager.offset(
                from: documentStart,
                to: fragment.rangeInElement.location
            )

            for line in fragment.textLineFragments {
                let lineStart = fragmentStart + line.characterRange.location
                let number = editor.lineNumber(at: lineStart)
                guard number != lastNumber else { continue }
                lastNumber = number

                let top = fragment.layoutFragmentFrame.minY
                    + line.typographicBounds.minY
                    + inset
                    - clipY
                let value = "\(number)" as NSString
                let size = value.size(withAttributes: attributes)
                value.draw(
                    at: NSPoint(
                        x: ruleThickness - size.width - 6,
                        y: top + (line.typographicBounds.height - size.height) / 2
                    ),
                    withAttributes: attributes
                )
            }

            return fragment.rangeInElement.endLocation.compare(end) != .orderedDescending
        }
    }

    func applyPalette(_ palette: ResolvedPalette?) {
        numberColor = palette?.colors.textGhost
            ?? palette?.colors.textDim
            ?? .tertiaryLabelColor
        needsDisplay = true
    }
}
