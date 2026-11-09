import AppKit

/// Settings (Command-comma): the features a writer can switch off, and what
/// goes on a printed page. Each change is written at once, and every window
/// follows through `.loomingsFeaturesChanged`.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let references = NSButton(checkboxWithTitle: "References", target: nil, action: nil)
    private let sidebar = NSButton(checkboxWithTitle: "File sidebar", target: nil, action: nil)
    private let perWindow = NSButton(radioButtonWithTitle: "Each window has its own folder", target: nil, action: nil)
    private let shared = NSButton(radioButtonWithTitle: "All windows share one folder", target: nil, action: nil)
    private let printQR = NSButton(checkboxWithTitle: "QR code on printed pages", target: nil, action: nil)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build(in: window)
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 340
        return label
    }

    private func build(in window: NSWindow) {
        let heading = NSTextField(labelWithString: "Features")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        for button in [references, sidebar, perWindow, shared, printQR] {
            button.target = self
            button.action = #selector(changed(_:))
        }
        // Radio buttons in one superview group themselves; a shared action
        // keeps the pair in step with the preference.
        let radios = NSStackView(views: [perWindow, shared])
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 4
        radios.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        let printing = NSTextField(labelWithString: "Printing")
        printing.font = .systemFont(ofSize: 13, weight: .semibold)

        let stack = NSStackView(views: [
            heading,
            references,
            note("The References menu and tab, citations and the reference list. Off: [@key] stays as typed."),
            sidebar,
            note("A list of the Markdown files in a folder, beside the editor. View > Show Sidebar toggles it."),
            radios,
            printing,
            printQR,
            note("The share link as a QR code at the end of a printed page or a PDF. The code holds the whole document. Off: the page ends with the text."),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: references)
        stack.setCustomSpacing(14, after: stack.views[3])
        stack.setCustomSpacing(20, after: radios)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            ])
        }
    }

    /// Reads the preferences into the controls.
    func sync() {
        references.state = EditorPreferences.referencesEnabled ? .on : .off
        sidebar.state = EditorPreferences.sidebarEnabled ? .on : .off
        perWindow.state = EditorPreferences.sidebarSharedFolder ? .off : .on
        shared.state = EditorPreferences.sidebarSharedFolder ? .on : .off
        perWindow.isEnabled = EditorPreferences.sidebarEnabled
        shared.isEnabled = EditorPreferences.sidebarEnabled
        printQR.state = EditorPreferences.printQRCode ? .on : .off
    }

    @objc private func changed(_ sender: NSButton) {
        EditorPreferences.referencesEnabled = references.state == .on
        EditorPreferences.sidebarEnabled = sidebar.state == .on
        EditorPreferences.printQRCode = printQR.state == .on
        if sender === shared { EditorPreferences.sidebarSharedFolder = true }
        if sender === perWindow { EditorPreferences.sidebarSharedFolder = false }
        sync()
        NotificationCenter.default.post(name: .loomingsFeaturesChanged, object: nil)
    }

    var printQRCodeIsOnForTesting: Bool { printQR.state == .on }
    func clickPrintQRCodeForTesting() { printQR.performClick(nil) }

    /// Escape closes the window, as in other Settings windows.
    override func cancelOperation(_ sender: Any?) {
        window?.performClose(sender)
    }

    func show() {
        sync()
        // The window comes back where the writer left it.
        if window?.setFrameUsingName("LoomingsSettings") != true { window?.center() }
        window?.setFrameAutosaveName("LoomingsSettings")
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
