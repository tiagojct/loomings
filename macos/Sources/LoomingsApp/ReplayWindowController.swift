import AppKit
import LoomingsTeaching
import LoomingsTheme

/// Plays a document's writing history back: a read-only page, a slider over
/// the steps, Play and Pause, and speeds. Pauses longer than five seconds
/// are shortened to one so a replay of a long session stays watchable.
@MainActor
final class ReplayWindowController: NSWindowController {
    private let entries: [HistoryEntry]
    private let textView = NSTextView()
    private let slider = NSSlider()
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let speedPopup = NSPopUpButton()
    private let timeLabel = NSTextField(labelWithString: "")
    private var step = 0
    private var timer: Timer?
    private static let speeds: [Double] = [1, 4, 16, 64]

    var stepCount: Int { entries.count }
    var shownText: String { textView.string }

    init(entries: [HistoryEntry], title: String, palette: ResolvedPalette?) {
        self.entries = entries
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Writing history: \(title)"
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build(palette: palette)
        show(step: max(0, entries.count - 1))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReplayWindowController is created in code")
    }

    private func build(palette: ResolvedPalette?) {
        guard let window else { return }
        let colors = palette?.colors
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont(name: "JetBrainsMono-Regular", size: 15) ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = colors?.text ?? .labelColor
        textView.backgroundColor = colors?.background ?? .textBackgroundColor
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Document at this step")
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = colors?.background ?? .textBackgroundColor

        slider.minValue = 0
        slider.maxValue = Double(max(0, entries.count - 1))
        slider.numberOfTickMarks = 0
        slider.target = self
        slider.action = #selector(scrub(_:))
        slider.setAccessibilityLabel("Step")

        playButton.target = self
        playButton.action = #selector(togglePlay(_:))
        playButton.bezelStyle = .rounded

        speedPopup.addItems(withTitles: Self.speeds.map { "\(Int($0))\u{00D7}" })
        speedPopup.selectItem(at: 1)
        speedPopup.setAccessibilityLabel("Speed")

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = colors?.textDim ?? .secondaryLabelColor
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let controls = NSStackView(views: [playButton, slider, speedPopup, timeLabel])
        controls.spacing = 12
        controls.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        let stack = NSStackView(views: [scroll, controls])
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
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.contentView = content
    }

    func show(step newStep: Int) {
        guard !entries.isEmpty else {
            textView.string = ""
            timeLabel.stringValue = "No history"
            return
        }
        step = min(max(0, newStep), entries.count - 1)
        textView.string = HistoryLog.reconstruct(entries, upTo: step)
        slider.doubleValue = Double(step)
        let date = Date(timeIntervalSince1970: entries[step].time)
        let time = date.formatted(date: .abbreviated, time: .standard)
        timeLabel.stringValue = "\(time) \u{00B7} step \(step + 1) of \(entries.count)"
    }

    @objc private func scrub(_ sender: NSSlider) {
        stop()
        show(step: Int(sender.doubleValue.rounded()))
    }

    @objc private func togglePlay(_ sender: Any?) {
        if timer != nil {
            stop()
        } else {
            if step >= entries.count - 1 { show(step: 0) }
            playButton.title = "Pause"
            scheduleNext()
        }
    }

    private func scheduleNext() {
        guard step < entries.count - 1 else {
            stop()
            return
        }
        let gap = entries[step + 1].time - entries[step].time
        let shortened = gap > 5 ? 1 : max(0, gap)
        let speed = Self.speeds[max(0, speedPopup.indexOfSelectedItem)]
        timer = Timer.scheduledTimer(withTimeInterval: max(0.02, shortened / speed), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.show(step: self.step + 1)
                self.scheduleNext()
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        playButton.title = "Play"
    }

    override func close() {
        stop()
        super.close()
    }
}
