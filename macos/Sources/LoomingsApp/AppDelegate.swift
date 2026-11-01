import AppKit
import LoomingsDocuments
import LoomingsEditor
import LoomingsShare
import LoomingsTeaching
import LoomingsTheme
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var recentMenu: NSMenu?
    private var shelfMenu: NSMenu?
    private var outlineMenu: NSMenu?
    private var learnItems: [LearnItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadLearnItems()
        buildMenu()

        ThemeManager.shared.applyAppearance()
        ThemeManager.shared.onChange = { [weak self] in
            self?.refreshAllWindows()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                for document in NSDocumentController.shared.documents {
                    (document as? LoomingsDocument)?.checkForExternalChange()
                }
                ThemeManager.shared.refreshForSystemAppearance()
            }
        }

        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ThemeManager.shared.refreshForSystemAppearance()
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        newDocument(nil)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func newDocument(_ sender: Any?) {
        let document = LoomingsDocument()
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = makeAppMenu()

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        fileMenuItem.submenu = makeFileMenu()

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = makeEditMenu()

        let formatMenuItem = NSMenuItem()
        mainMenu.addItem(formatMenuItem)
        formatMenuItem.submenu = makeFormatMenu()

        let themeMenuItem = NSMenuItem()
        mainMenu.addItem(themeMenuItem)
        themeMenuItem.submenu = makeThemeMenu()

        let learnMenuItem = NSMenuItem()
        mainMenu.addItem(learnMenuItem)
        learnMenuItem.submenu = makeLearnMenu()

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        viewMenuItem.submenu = makeViewMenu()

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        windowMenuItem.submenu = makeWindowMenu()
        NSApp.windowsMenu = windowMenuItem.submenu

        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: "Loomings")

        let aboutItem = NSMenuItem(
            title: "About Loomings",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Hide Loomings",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Loomings",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return menu
    }

    private func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")

        let newItem = NSMenuItem(
            title: "New",
            action: #selector(newDocument(_:)),
            keyEquivalent: "n"
        )
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(
            withTitle: "Open…",
            action: #selector(NSDocumentController.openDocument(_:)),
            keyEquivalent: "o"
        )

        let recent = NSMenu(title: "Open Recent")
        recent.delegate = self
        recentMenu = recent
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        menu.addItem(recentItem)

        let shelf = NSMenu(title: "Open from Shelf")
        shelf.delegate = self
        shelfMenu = shelf
        let shelfItem = NSMenuItem(title: "Open from Shelf", action: nil, keyEquivalent: "")
        shelfItem.submenu = shelf
        menu.addItem(shelfItem)

        let importItem = NSMenuItem(
            title: "Import from Browser Export…",
            action: #selector(importFromBrowser(_:)),
            keyEquivalent: ""
        )
        importItem.target = self
        menu.addItem(importItem)
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Save",
            action: #selector(NSDocument.save(_:)),
            keyEquivalent: "s"
        )

        let saveAs = NSMenuItem(
            title: "Save As…",
            action: #selector(NSDocument.saveAs(_:)),
            keyEquivalent: "s"
        )
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)

        let saveToShelf = NSMenuItem(
            title: "Save to Shelf",
            action: #selector(LoomingsDocument.saveToShelf(_:)),
            keyEquivalent: "s"
        )
        saveToShelf.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(saveToShelf)
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Duplicate",
            action: #selector(NSDocument.duplicate(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Rename…",
            action: #selector(NSDocument.rename(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Revert to Saved",
            action: #selector(NSDocument.revertToSaved(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Browse All Versions…",
            action: #selector(NSDocument.browseVersions(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        let history = NSMenu(title: "Writing History")
        history.addItem(withTitle: "Record Writing History", action: #selector(EditorWindowController.toggleWritingHistory(_:)), keyEquivalent: "")
        history.addItem(withTitle: "Replay Writing History\u{2026}", action: #selector(EditorWindowController.replayWritingHistory(_:)), keyEquivalent: "")
        history.addItem(.separator())
        history.addItem(withTitle: "Delete Writing History\u{2026}", action: #selector(EditorWindowController.deleteWritingHistory(_:)), keyEquivalent: "")
        let historyItem = NSMenuItem(title: "Writing History", action: nil, keyEquivalent: "")
        historyItem.submenu = history
        menu.addItem(historyItem)

        return menu
    }

    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(findItem("Find…", .showFindInterface, "f", []))
        find.addItem(findItem("Find and Replace…", .showReplaceInterface, "f", [.option]))
        find.addItem(.separator())
        find.addItem(findItem("Find Next", .nextMatch, "g", []))
        find.addItem(findItem("Find Previous", .previousMatch, "g", [.shift]))
        find.addItem(.separator())
        find.addItem(findItem("Use Selection for Find", .setSearchString, "e", []))
        find.addItem(findItem("Replace All", .replaceAll, "", []))
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        menu.addItem(findItem)

        return menu
    }

    private func findItem(
        _ title: String,
        _ action: NSTextFinder.Action,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(NSTextView.performTextFinderAction(_:)),
            keyEquivalent: key
        )
        item.tag = action.rawValue
        item.keyEquivalentModifierMask = NSEvent.ModifierFlags.command.union(modifiers)
        return item
    }

    // MARK: - Learn

    private struct LearnItem {
        let title: String
        let content: String
        var file: String? = nil
    }

    /// Opens a bundled lesson in Split view, by file name ("02-lists-quotes.md").
    func openLesson(named file: String) {
        guard let item = learnItems.first(where: { $0.file == file }) else { return }
        openLearnContent(item)
    }

    private func loadLearnItems() {
        var items: [LearnItem] = []
        let root = Bundle.main.resourceURL

        if let lessonsURL = root?.appendingPathComponent("lessons"),
           let files = try? FileManager.default.contentsOfDirectory(
               at: lessonsURL,
               includingPropertiesForKeys: nil
           ) {
            let sorted = files
                .filter { $0.pathExtension == "md" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for file in sorted {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                items.append(LearnItem(
                    title: lessonTitle(content) ?? file.deletingPathExtension().lastPathComponent,
                    content: content,
                    file: file.lastPathComponent
                ))
            }
        }

        if let example = root?.appendingPathComponent("example.md"),
           let content = try? String(contentsOf: example, encoding: .utf8) {
            items.append(LearnItem(title: "Moby-Dick, chapter 1", content: content))
        }
        if let cheatsheet = root?.appendingPathComponent("cheatsheet.md"),
           let content = try? String(contentsOf: cheatsheet, encoding: .utf8) {
            items.append(LearnItem(title: "Markdown cheatsheet", content: content))
        }
        learnItems = items
    }

    private func lessonTitle(_ content: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func makeLearnMenu() -> NSMenu {
        let menu = NSMenu(title: "Learn")
        if learnItems.isEmpty {
            let missing = NSMenuItem(title: "Teaching material unavailable", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
            return menu
        }

        for (index, item) in learnItems.enumerated() {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(openLearnItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = index
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc private func openLearnItem(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              learnItems.indices.contains(index) else {
            return
        }
        openLearnContent(learnItems[index])
    }

    private func openLearnContent(_ item: LearnItem) {
        let document = LoomingsDocument()
        document.pendingText = item.content
        document.displayName = item.title
        if let file = item.file {
            let checks = LessonChecks.checks(for: file)
            if !checks.isEmpty {
                document.attachedChecks = AttachedChecks(checks: checks, after: item.content)
            }
        }
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        if let controller = document.windowControllers.first as? EditorWindowController {
            controller.setViewMode(.split)
        }
    }

    // MARK: - Share links

    @objc private func openShareLink(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Open Share Link"
        alert.informativeText = "Paste a Loomings link. A link with a document payload is imported; other web links open in the browser."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.stringValue = NSPasteboard.general.string(forType: .string) ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        do {
            let payload = try ShareLink.parse(string: value)
            applySharedAppearance(payload)
            let document = LoomingsDocument()
            document.pendingText = payload.text
            document.displayName = "Shared Document"
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        } catch ShareLinkError.notShareLink {
            if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
            } else {
                presentError(ShareLinkError.notShareLink)
            }
        } catch {
            presentError(error)
        }
    }

    private func applySharedAppearance(_ payload: SharePayload) {
        if let family = payload.family,
           ThemeManager.shared.library?.families[family] != nil {
            ThemeManager.shared.family = family
        }
        if let mode = payload.mode.flatMap(ThemeMode.init(rawValue:)) {
            ThemeManager.shared.mode = mode
        }
        ThemeManager.shared.applyAppearance()
        refreshAllWindows()
    }

    private func makeThemeMenu() -> NSMenu {
        let menu = NSMenu(title: "Theme")
        let library = ThemeManager.shared.library

        let modes = NSMenu(title: "Appearance")
        for mode in ThemeMode.allCases {
            let item = NSMenuItem(
                title: mode.label,
                action: #selector(setThemeMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            modes.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        modeItem.submenu = modes
        menu.addItem(modeItem)
        menu.addItem(.separator())

        if let library {
            for family in library.familyLabels {
                let item = NSMenuItem(
                    title: family.label,
                    action: #selector(setThemeFamily(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = family.id
                menu.addItem(item)
            }
        } else {
            let missing = NSMenuItem(title: "Palettes unavailable", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
        }

        return menu
    }

    @objc private func setThemeMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ThemeMode(rawValue: raw) else {
            return
        }
        ThemeManager.shared.mode = mode
        ThemeManager.shared.applyAppearance()
        refreshAllWindows()
    }

    @objc private func setThemeFamily(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? String else { return }
        ThemeManager.shared.family = family
        refreshAllWindows()
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        let credits = NSMutableAttributedString(
            string: """
            A markdown writing app. The shapes loom before they take form.

            MIT licensed. Colours from Ensigns (ensigns.tiagojacinto.eu, CC BY 4.0).
            Typefaces: JetBrains Mono and Source Serif 4 (SIL Open Font License).

            loomings.tiagojacinto.eu
            github.com/tiagojct/loomings
            """
        )
        credits.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ],
            range: NSRange(location: 0, length: credits.length)
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "Loomings",
            .version: version,
        ])
    }

    private func makeFormatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(
            withTitle: "Bold",
            action: #selector(EditorWindowController.toggleBold(_:)),
            keyEquivalent: "b"
        )
        menu.addItem(
            withTitle: "Italic",
            action: #selector(EditorWindowController.toggleItalic(_:)),
            keyEquivalent: "i"
        )
        menu.addItem(
            withTitle: "Inline Code",
            action: #selector(EditorWindowController.toggleInlineCode(_:)),
            keyEquivalent: "`"
        )
        menu.addItem(
            withTitle: "Link",
            action: #selector(EditorWindowController.insertLink(_:)),
            keyEquivalent: "k"
        )
        return menu
    }

    private func makeViewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")

        menu.addItem(
            withTitle: "Write",
            action: #selector(EditorWindowController.setWriteMode(_:)),
            keyEquivalent: "1"
        )
        menu.addItem(
            withTitle: "Split",
            action: #selector(EditorWindowController.setSplitMode(_:)),
            keyEquivalent: "\\"
        )
        let previewMode = NSMenuItem(
            title: "Preview",
            action: #selector(EditorWindowController.setPreviewMode(_:)),
            keyEquivalent: "p"
        )
        previewMode.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(previewMode)
        menu.addItem(.separator())

        let outline = NSMenu(title: "Go to Heading")
        outline.delegate = self
        outlineMenu = outline
        let outlineItem = NSMenuItem(title: "Go to Heading", action: nil, keyEquivalent: "o")
        outlineItem.keyEquivalentModifierMask = [.command, .shift]
        outlineItem.submenu = outline
        menu.addItem(outlineItem)
        menu.addItem(.separator())

        let bigger = NSMenuItem(
            title: "Bigger",
            action: #selector(increaseFontSize(_:)),
            keyEquivalent: "="
        )
        bigger.target = self
        menu.addItem(bigger)

        let smaller = NSMenuItem(
            title: "Smaller",
            action: #selector(decreaseFontSize(_:)),
            keyEquivalent: "-"
        )
        smaller.target = self
        menu.addItem(smaller)

        let width = NSMenu(title: "Column Width")
        for candidate in ColumnWidth.allCases {
            let item = NSMenuItem(
                title: candidate.label,
                action: #selector(setColumnWidth(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = candidate.rawValue
            width.addItem(item)
        }
        let widthItem = NSMenuItem(title: "Column Width", action: nil, keyEquivalent: "")
        widthItem.submenu = width
        menu.addItem(widthItem)

        let lineNumbers = NSMenuItem(
            title: "Line Numbers",
            action: #selector(toggleLineNumbers(_:)),
            keyEquivalent: ""
        )
        lineNumbers.target = self
        menu.addItem(lineNumbers)

        let stats = NSMenuItem(
            title: "Statistics",
            action: #selector(toggleStats(_:)),
            keyEquivalent: "l"
        )
        stats.keyEquivalentModifierMask = [.command, .shift]
        stats.target = self
        menu.addItem(stats)

        let focus = NSMenuItem(
            title: "Focus Mode",
            action: #selector(toggleFocusMode(_:)),
            keyEquivalent: "d"
        )
        focus.keyEquivalentModifierMask = [.command, .shift]
        focus.target = self
        menu.addItem(focus)

        let typewriter = NSMenuItem(
            title: "Typewriter Scrolling",
            action: #selector(toggleTypewriter(_:)),
            keyEquivalent: "y"
        )
        typewriter.keyEquivalentModifierMask = [.command, .shift]
        typewriter.target = self
        menu.addItem(typewriter)

        let wordGoal = NSMenuItem(
            title: "Word Goal",
            action: #selector(cycleWordGoal(_:)),
            keyEquivalent: ""
        )
        wordGoal.target = self
        menu.addItem(wordGoal)

        let smart = NSMenuItem(
            title: "Smart Typography",
            action: #selector(toggleSmartTypography(_:)),
            keyEquivalent: ""
        )
        smart.target = self
        menu.addItem(smart)
        menu.addItem(.separator())

        let projector = NSMenuItem(
            title: "Projector Mode",
            action: #selector(EditorWindowController.toggleProjectorMode(_:)),
            keyEquivalent: "p"
        )
        projector.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(projector)

        let fullScreen = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(fullScreen)

        return menu
    }

    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        return menu
    }

    // MARK: - Dynamic menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === recentMenu {
            rebuildRecentMenu(menu)
        } else if menu === shelfMenu {
            rebuildShelfMenu(menu)
        } else if menu === outlineMenu {
            rebuildOutlineMenu(menu)
        }
    }

    private func rebuildOutlineMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller = NSApp.keyWindow?.windowController as? EditorWindowController else {
            let empty = NSMenuItem(title: "No Document", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let headings = controller.editor.outline
        guard !headings.isEmpty else {
            let empty = NSMenuItem(title: "No Headings", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for (index, heading) in headings.enumerated() {
            let item = NSMenuItem(
                title: heading.title.isEmpty ? "(empty heading)" : heading.title,
                action: #selector(jumpToHeading(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = index
            item.indentationLevel = min(4, max(0, heading.level - 1))
            menu.addItem(item)
        }
    }

    @objc private func jumpToHeading(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              let controller = NSApp.keyWindow?.windowController as? EditorWindowController,
              controller.editor.outline.indices.contains(index) else {
            return
        }
        controller.jump(to: controller.editor.outline[index])
    }

    private func rebuildRecentMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for url in urls.prefix(12) {
                let item = NSMenuItem(
                    title: url.deletingPathExtension().lastPathComponent,
                    action: #selector(openRecentDocument(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = url
                item.toolTip = url.path
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(
            title: "Clear Menu",
            action: #selector(clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clear.target = self
        menu.addItem(clear)
    }

    private func rebuildShelfMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let shelf = LocalShelf.shared
        let entries = (try? shelf.entries()) ?? []
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No Shelf Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in entries.prefix(24) {
                let item = NSMenuItem(
                    title: entry.title,
                    action: #selector(openShelfEntry(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id.uuidString
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let reveal = NSMenuItem(
            title: "Open Shelf Folder",
            action: #selector(revealShelf(_:)),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)
    }

    // MARK: - Editor preferences

    @objc private func increaseFontSize(_ sender: Any?) {
        EditorPreferences.fontSize = EditorPreferences.nextFontSize(
            after: EditorPreferences.fontSize,
            delta: 1
        )
        refreshAllWindows()
    }

    @objc private func decreaseFontSize(_ sender: Any?) {
        EditorPreferences.fontSize = EditorPreferences.nextFontSize(
            after: EditorPreferences.fontSize,
            delta: -1
        )
        refreshAllWindows()
    }

    @objc private func setColumnWidth(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let width = ColumnWidth(rawValue: raw) else {
            return
        }
        EditorPreferences.columnWidth = width
        refreshAllWindows()
    }

    @objc private func toggleLineNumbers(_ sender: Any?) {
        EditorPreferences.showLineNumbers.toggle()
        refreshAllWindows()
    }

    @objc private func toggleStats(_ sender: Any?) {
        EditorPreferences.showStats.toggle()
        refreshAllWindows()
    }

    @objc private func toggleSmartTypography(_ sender: Any?) {
        EditorPreferences.smartTypography.toggle()
        refreshAllWindows()
    }

    @objc private func toggleTypewriter(_ sender: Any?) {
        EditorPreferences.typewriter.toggle()
        refreshAllWindows()
    }

    @objc private func toggleFocusMode(_ sender: Any?) {
        guard let controller = NSApp.keyWindow?.windowController as? EditorWindowController else {
            return
        }
        let enabled = !controller.editor.isFocusMode
        for document in NSDocumentController.shared.documents {
            for windowController in document.windowControllers {
                (windowController as? EditorWindowController)?.editor.setFocusMode(enabled)
            }
        }
    }

    @objc private func cycleWordGoal(_ sender: Any?) {
        EditorPreferences.wordGoal = EditorPreferences.nextWordGoal(
            after: EditorPreferences.wordGoal
        )
        refreshAllWindows()
    }

    private func refreshAllWindows() {
        for document in NSDocumentController.shared.documents {
            for controller in document.windowControllers {
                (controller as? EditorWindowController)?.applyPreferences()
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = EditorPreferences.showLineNumbers ? .on : .off
        case #selector(toggleStats(_:)):
            menuItem.state = EditorPreferences.showStats ? .on : .off
        case #selector(toggleSmartTypography(_:)):
            menuItem.state = EditorPreferences.smartTypography ? .on : .off
        case #selector(toggleTypewriter(_:)):
            menuItem.state = EditorPreferences.typewriter ? .on : .off
        case #selector(toggleFocusMode(_:)):
            let controller = NSApp.keyWindow?.windowController as? EditorWindowController
            menuItem.state = (controller?.editor.isFocusMode ?? false) ? .on : .off
            return controller != nil
        case #selector(cycleWordGoal(_:)):
            let goal = EditorPreferences.wordGoal
            menuItem.title = goal == 0 ? "Word Goal: Off" : "Word Goal: \(goal)"
        case #selector(setColumnWidth(_:)):
            if let raw = menuItem.representedObject as? String,
               let width = ColumnWidth(rawValue: raw) {
                menuItem.state = EditorPreferences.columnWidth == width ? .on : .off
            }
        case #selector(setThemeMode(_:)):
            if let raw = menuItem.representedObject as? String {
                menuItem.state = ThemeManager.shared.mode.rawValue == raw ? .on : .off
            }
        case #selector(setThemeFamily(_:)):
            if let family = menuItem.representedObject as? String {
                menuItem.state = ThemeManager.shared.family == family ? .on : .off
            }
        default:
            break
        }
        return true
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url)
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    @objc private func openShelfEntry(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value) else {
            return
        }
        do {
            let (entry, _) = try LocalShelf.shared.read(id: id)
            open(LocalShelf.shared.contentURL(for: entry))
        } catch {
            presentError(error)
        }
    }

    @objc private func revealShelf(_ sender: Any?) {
        let shelf = LocalShelf.shared
        try? FileManager.default.createDirectory(
            at: shelf.root,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([shelf.root])
    }

    @objc private func importFromBrowser(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Import Browser Shelf Export"
        panel.message = "Choose Markdown files exported from the browser app. They are copied into the local shelf."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK else { return }

        var failures: [String] = []
        for url in panel.urls {
            do {
                let entry = try LocalShelf.shared.importFile(at: url)
                open(LocalShelf.shared.contentURL(for: entry))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some files were not imported"
            alert.informativeText = failures.joined(separator: "\n")
            alert.runModal()
        }
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { _, _, error in
            if let error {
                NSApp.presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
