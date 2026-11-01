import AppKit
import LoomingsTheme

/// Colours for the title-bar controls, from the palette or, without one,
/// from the system.
struct ChromeColors {
    let track: NSColor
    let raised: NSColor
    let border: NSColor
    let ink: NSColor
    let dimInk: NSColor

    init(_ palette: ResolvedPalette?) {
        if let colors = palette?.colors {
            track = colors.backgroundDeep
            raised = colors.backgroundElevated
            border = colors.borderColor
            ink = colors.text
            dimInk = colors.textDim
        } else {
            track = .quaternaryLabelColor
            raised = .controlBackgroundColor
            border = .separatorColor
            ink = .labelColor
            dimInk = .secondaryLabelColor
        }
    }
}

/// Write / Split / Preview as one control: equal segments, one height, and
/// the selected segment raised on the palette's elevated ground.
@MainActor
final class ModeSwitch: NSView {
    static let height: CGFloat = 28

    var onSelect: ((Int) -> Void)?
    var selectedIndex: Int = 0 {
        didSet {
            for (index, segment) in segments.enumerated() {
                segment.isActive = index == selectedIndex
            }
        }
    }

    private var segments: [ModeSegment] = []
    private var colors = ChromeColors(nil)

    init(labels: [String]) {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 40
        let segmentWidth = (widest + 20).rounded(.up)
        let inset: CGFloat = 2
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: segmentWidth * CGFloat(labels.count) + inset * 2,
            height: Self.height
        ))
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("View mode")

        for (index, label) in labels.enumerated() {
            let segment = ModeSegment(label: label, font: font)
            segment.frame = NSRect(
                x: inset + segmentWidth * CGFloat(index), y: inset,
                width: segmentWidth, height: Self.height - inset * 2
            )
            segment.target = self
            segment.action = #selector(pick(_:))
            segment.tag = index
            addSubview(segment)
            segments.append(segment)
        }
        selectedIndex = 0
        segments.first?.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ModeSwitch is created in code")
    }

    override var intrinsicContentSize: NSSize { frame.size }

    func applyPalette(_ palette: ResolvedPalette?) {
        colors = ChromeColors(palette)
        for segment in segments {
            segment.colors = colors
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        colors.track.withAlphaComponent(0.55).setFill()
        track.fill()
    }

    @objc private func pick(_ sender: ModeSegment) {
        selectedIndex = sender.tag
        onSelect?(sender.tag)
    }
}

@MainActor
private final class ModeSegment: NSButton {
    let label: String
    let labelFont: NSFont
    var colors = ChromeColors(nil) { didSet { needsDisplay = true } }
    var isActive = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(isActive)
        }
    }

    init(label: String, font: NSFont) {
        self.label = label
        self.labelFont = font
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ModeSegment is created in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            colors.raised.setFill()
            shape.fill()
            colors.border.withAlphaComponent(0.7).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: isActive ? colors.ink : colors.dimInk,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(
            at: NSPoint(
                x: ((bounds.width - size.width) / 2).rounded(),
                y: ((bounds.height - size.height) / 2).rounded()
            ),
            withAttributes: attributes
        )
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

/// A square title-bar tool: one symbol, one size, one weight, centred in a
/// fixed cell so a row of them lines up whatever each glyph's shape.
@MainActor
final class ToolbarIconButton: NSButton {
    static let side: CGFloat = 28

    private let symbolName: String
    private var colors = ChromeColors(nil)
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    private var restoreWork: DispatchWorkItem?

    init(symbol: String, label: String) {
        symbolName = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        toolTip = label
        setAccessibilityLabel(label)
        setSymbol(symbol)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ToolbarIconButton is created in code")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    func applyPalette(_ palette: ResolvedPalette?) {
        colors = ChromeColors(palette)
        contentTintColor = colors.dimInk
        needsDisplay = true
    }

    /// Shows a confirming symbol for a moment, then the usual one.
    func confirm(with symbol: String = "checkmark") {
        restoreWork?.cancel()
        setSymbol(symbol)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setSymbol(self.symbolName)
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func setSymbol(_ name: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular, scale: .medium)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            let shape = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
            colors.track.withAlphaComponent(isHighlighted ? 0.9 : 0.55).setFill()
            shape.fill()
        }
        super.draw(dirtyRect)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

/// A legacy (always visible) scroller whose track takes the document ground
/// instead of the system's grey slot. Overlay scrollers draw no track.
final class ThemedScroller: NSScroller {
    var trackColor: NSColor? { didSet { needsDisplay = true } }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard let trackColor else {
            super.drawKnobSlot(in: slotRect, highlight: flag)
            return
        }
        trackColor.setFill()
        slotRect.fill()
    }
}
