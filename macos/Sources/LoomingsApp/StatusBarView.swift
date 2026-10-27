import AppKit
import LoomingsEditor

@MainActor
final class StatusBarView: NSView {
    private let positionLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let wordsLabel = NSTextField(labelWithString: "0 w")
    private let charactersLabel = NSTextField(labelWithString: "0 c")
    private let linesLabel = NSTextField(labelWithString: "0 ln")
    private let readingLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let labels = [positionLabel, wordsLabel, charactersLabel, linesLabel, readingLabel]
        for label in labels {
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
        }

        let left = NSStackView(views: [positionLabel])
        left.orientation = .horizontal
        left.spacing = 12

        let right = NSStackView(views: [wordsLabel, charactersLabel, linesLabel, readingLabel])
        right.orientation = .horizontal
        right.spacing = 12

        let stack = NSStackView(views: [left, right])
        stack.orientation = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusBarView is created in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Resolve the dynamic system colour while drawing so Dark/Light
        // appearance changes are reflected. A layer background captured at
        // init stays at the old appearance.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        needsDisplay = true
    }

    func update(position: String, statistics: SelectionStatistics?) {
        positionLabel.stringValue = position
        guard let statistics else {
            clearDocumentStatistics()
            return
        }
        wordsLabel.stringValue = "\(statistics.words) w"
        charactersLabel.stringValue = "\(statistics.characters) c"
        linesLabel.stringValue = "\(statistics.lines) ln (sel)"
        readingLabel.stringValue = ""
    }

    func update(
        position: String,
        words: Int,
        characters: Int,
        lines: Int,
        reading: String,
        goal: Int
    ) {
        positionLabel.stringValue = position
        if goal > 0 {
            let percentage = min(100, Int((Double(words) / Double(goal) * 100).rounded()))
            wordsLabel.stringValue = "\(words) / \(goal) w (\(percentage)%)"
        } else {
            wordsLabel.stringValue = "\(words) w"
        }
        charactersLabel.stringValue = "\(characters) c"
        linesLabel.stringValue = "\(lines) ln"
        readingLabel.stringValue = reading
    }

    private func clearDocumentStatistics() {
        wordsLabel.stringValue = ""
        charactersLabel.stringValue = ""
        linesLabel.stringValue = ""
        readingLabel.stringValue = ""
    }
}
