import AppKit
import LoomingsTeaching
import LoomingsTheme

/// Popover content for the teaching features: checker notes, marker
/// explanations, exercise checklists. Plain AppKit stacks; the popover takes
/// the window's appearance.
@MainActor
enum TeachingPopovers {
    static let width: CGFloat = 360

    @discardableResult
    static func show(_ content: NSView, relativeTo rect: NSRect, of view: NSView, palette: ResolvedPalette?) -> NSPopover {
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        if let palette {
            popover.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        }
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        return popover
    }

    /// A column of rows inside a scroll view no taller than `maxHeight`.
    static func column(_ rows: [NSView], maxHeight: CGFloat = 420) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            row.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        }
        let fitting = stack.fittingSize
        let height = min(maxHeight, fitting.height)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = fitting.height > maxHeight
        let flipped = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: fitting.height))
        flipped.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: flipped.topAnchor),
            stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
        ])
        scroll.documentView = flipped
        return scroll
    }

    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.isSelectable = false
        return field
    }

    static func button(_ title: String, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    /// One row per checker note: message, its line, and Fix / Go to line.
    static func notes(
        _ issues: [LintIssue],
        line: (LintIssue) -> Int,
        onFix: @escaping (LintIssue) -> Void,
        onGo: @escaping (LintIssue) -> Void
    ) -> NSView {
        let rows: [NSView] = issues.map { issue in
            let message = label(issue.message)
            var buttons: [NSView] = []
            if let fix = issue.fix {
                buttons.append(button(fix.title) { onFix(issue) })
            }
            buttons.append(button("Go to line \(line(issue))") { onGo(issue) })
            let actions = NSStackView(views: buttons)
            actions.spacing = 8
            let row = NSStackView(views: [message, actions])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 6
            return row
        }
        return column(rows)
    }
}

extension TeachingPopovers {
    /// What a marker means, with a way to the lesson that teaches it.
    static func explanation(_ explanation: MarkerExplanation, onLesson: (() -> Void)?) -> NSView {
        var rows: [NSView] = [
            label(explanation.title, size: 14, weight: .semibold),
            label(explanation.body),
        ]
        if let onLesson {
            rows.append(button("Open the lesson", action: onLesson))
        }
        let content = column(rows)
        return content
    }
}

extension TeachingPopovers {
    /// The exercise checklist: each check with a tick or an open circle,
    /// then any directive that could not be understood.
    static func checklist(_ results: [CheckResult], notes: [DirectiveNote]) -> NSView {
        var rows: [NSView] = []
        for result in results {
            let symbol = NSImage(
                systemSymbolName: result.passed ? "checkmark.circle.fill" : "circle",
                accessibilityDescription: result.passed ? "Done" : "Not yet"
            )
            let mark = NSImageView(image: symbol ?? NSImage())
            mark.contentTintColor = result.passed ? .controlAccentColor : .tertiaryLabelColor
            mark.setContentHuggingPriority(.required, for: .horizontal)
            let text = NSStackView(views: [label(result.label, weight: .medium), label(result.detail, size: 11, secondary: true)])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            let row = NSStackView(views: [mark, text])
            row.alignment = .top
            row.spacing = 10
            rows.append(row)
        }
        for note in notes {
            rows.append(label("Line \(note.line + 1): \(note.message)", size: 12, secondary: true))
        }
        return column(rows)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A button that runs a closure, so popover rows need no target objects.
final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(run)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClosureButton is created in code")
    }

    @objc private func run() { handler() }
}
