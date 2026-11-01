import AppKit
import LoomingsTheme

/// Projector mode's values. It changes how the window looks for a class at
/// a distance; it never writes a preference, so turning it off restores the
/// writer's own settings exactly.
enum ProjectorMode {
    static let editorFontSize: CGFloat = 28
    static let previewBodySize: CGFloat = 26
    static let columnWidth: ColumnWidth = .wide
}

/// A short caption at the bottom of the window naming the markup just used,
/// so a room can follow what the teacher types.
@MainActor
final class MarkupOverlay: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private var background: NSColor = .windowBackgroundColor

    var text: String? { isHidden ? nil : label.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        label.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkupOverlay is created in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func applyPalette(_ palette: ResolvedPalette?) {
        background = palette?.colors.backgroundElevated ?? .windowBackgroundColor
        label.textColor = palette?.colors.text ?? .labelColor
        border = palette?.colors.borderColor ?? .separatorColor
        needsDisplay = true
    }

    private var border: NSColor = .separatorColor

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        background.setFill()
        shape.fill()
        border.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    /// Shows `text` and fades it out after 1.6 s.
    func show(_ text: String) {
        hideWork?.cancel()
        label.stringValue = text
        setAccessibilityLabel(text)
        alphaValue = 1
        isHidden = false
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.low.rawValue,
        ])
        let work = DispatchWorkItem { [weak self] in self?.fade() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        isHidden = true
    }

    private func fade() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.isHidden = true
            }
        })
    }
}
