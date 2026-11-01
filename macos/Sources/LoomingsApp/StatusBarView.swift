import AppKit
import LoomingsEditor
import LoomingsTheme

@MainActor
final class StatusBarView: NSView {
    private let positionLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let wordsLabel = NSTextField(labelWithString: "0 words")
    private let charactersLabel = NSTextField(labelWithString: "0 characters")
    private let linesLabel = NSTextField(labelWithString: "0 lines")
    private let readingLabel = NSTextField(labelWithString: "")
    private var palette: ResolvedPalette?

    private static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        let digits = number.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(digits) \(value == 1 ? singular : plural)"
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let labels = [positionLabel, wordsLabel, charactersLabel, linesLabel, readingLabel]
        for label in labels {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
        }

        let left = NSStackView(views: [positionLabel])
        left.orientation = .horizontal
        left.spacing = 12

        let right = NSStackView(views: [wordsLabel, charactersLabel, linesLabel, readingLabel])
        right.orientation = .horizontal
        right.spacing = 16

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
        (palette?.colors.background ?? .windowBackgroundColor).setFill()
        bounds.fill()
        (palette?.colors.borderColor ?? .separatorColor).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    override var isFlipped: Bool { false }

    func applyPalette(_ palette: ResolvedPalette?) {
        self.palette = palette
        let color = palette?.colors.textDim ?? .secondaryLabelColor
        for label in [positionLabel, wordsLabel, charactersLabel, linesLabel, readingLabel] {
            label.textColor = color
        }
        needsDisplay = true
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
        wordsLabel.stringValue = Self.count(statistics.words, "word", "words")
        charactersLabel.stringValue = Self.count(statistics.characters, "character", "characters")
        linesLabel.stringValue = Self.count(statistics.lines, "line", "lines")
        readingLabel.stringValue = "selected"
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
            let total = Self.number.string(from: NSNumber(value: goal)) ?? "\(goal)"
            let done = Self.number.string(from: NSNumber(value: words)) ?? "\(words)"
            wordsLabel.stringValue = "\(done) of \(total) words (\(percentage)%)"
        } else {
            wordsLabel.stringValue = Self.count(words, "word", "words")
        }
        charactersLabel.stringValue = Self.count(characters, "character", "characters")
        linesLabel.stringValue = Self.count(lines, "line", "lines")
        readingLabel.stringValue = reading.isEmpty ? "" : reading + " read"
    }

    private func clearDocumentStatistics() {
        wordsLabel.stringValue = ""
        charactersLabel.stringValue = ""
        linesLabel.stringValue = ""
        readingLabel.stringValue = ""
    }
}
