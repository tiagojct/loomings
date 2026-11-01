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
    /// Teaching items (notes, exercise, section), shown only when they apply.
    private let notesButton = StatusBarView.makeItemButton()
    var onNotesClick: (() -> Void)?

    private static func makeItemButton() -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.isHidden = true
        button.setButtonType(.momentaryChange)
        return button
    }

    var notesTitle: String? { notesButton.isHidden ? nil : notesButton.title }

    private let exerciseButton = StatusBarView.makeItemButton()
    var onExerciseClick: (() -> Void)?
    var exerciseTitle: String? { exerciseButton.isHidden ? nil : exerciseButton.title }
    private var exerciseDone = false

    /// "Exercise 2 of 4", or "Exercise done"; hidden when there are no checks.
    func setExercise(passed: Int, total: Int, notes: Int) {
        exerciseButton.isHidden = total == 0 && notes == 0
        exerciseDone = total > 0 && passed == total
        if total == 0 {
            exerciseButton.title = notes == 1 ? "1 check not understood" : "\(notes) checks not understood"
        } else {
            exerciseButton.title = exerciseDone ? "Exercise done" : "Exercise \(passed) of \(total)"
        }
        exerciseButton.setAccessibilityLabel(exerciseButton.title)
        styleItems()
    }

    private let sectionLabel = NSTextField(labelWithString: "")
    private var sectionOver = false
    var sectionTitle: String? { sectionLabel.isHidden ? nil : sectionLabel.stringValue }

    /// The caret's section against its word limit; nil hides it.
    func setSection(title: String?, words: Int, limit: Int) {
        guard let title else {
            sectionLabel.isHidden = true
            return
        }
        sectionLabel.isHidden = false
        sectionOver = words > limit
        let number = Self.number
        let done = number.string(from: NSNumber(value: words)) ?? "\(words)"
        let total = number.string(from: NSNumber(value: limit)) ?? "\(limit)"
        sectionLabel.stringValue = "\(title) \(done) of \(total) words"
        sectionLabel.setAccessibilityLabel(sectionOver ? "\(sectionLabel.stringValue), over the limit" : sectionLabel.stringValue)
        styleItems()
    }

    @objc private func exerciseClicked(_ sender: Any?) {
        onExerciseClick?()
    }

    func setNotes(count: Int) {
        notesButton.isHidden = count == 0
        notesButton.title = count == 1 ? "1 note" : "\(count) notes"
        notesButton.setAccessibilityLabel(count == 1 ? "1 Markdown note" : "\(count) Markdown notes")
        styleItems()
    }

    private func styleItems() {
        sectionLabel.textColor = sectionOver
            ? (palette?.colors.accentColor ?? .systemRed)
            : (palette?.colors.textDim ?? .secondaryLabelColor)
        let color = palette?.colors.linkColor ?? .linkColor
        for button in [notesButton, exerciseButton] {
            let color = button === exerciseButton && exerciseDone
                ? (palette?.colors.accentColor ?? .controlAccentColor)
                : color
            button.contentTintColor = color
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: button.font ?? NSFont.systemFont(ofSize: 11),
                .foregroundColor: color,
            ])
        }
    }

    @objc private func notesClicked(_ sender: Any?) {
        onNotesClick?()
    }

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

        notesButton.target = self
        notesButton.action = #selector(notesClicked(_:))
        exerciseButton.target = self
        exerciseButton.action = #selector(exerciseClicked(_:))
        sectionLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sectionLabel.lineBreakMode = .byTruncatingMiddle
        sectionLabel.isHidden = true
        let left = NSStackView(views: [positionLabel, notesButton, exerciseButton, sectionLabel])
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
        styleItems()
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
