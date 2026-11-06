import AppKit
import LoomingsDocuments
import LoomingsTheme

/// The file sidebar: one folder as a tree of sub-folders and writing files.
/// It lists lazily, one folder at a time, so a large folder costs nothing
/// until it opens. A file opens as an ordinary document.
@MainActor
final class SidebarView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Node {
        let entry: FolderEntry
        var children: [Node]?
        init(_ entry: FolderEntry) { self.entry = entry }
    }

    static let minimumWidth: CGFloat = 160
    static let defaultWidth: CGFloat = 220

    var onOpen: ((URL) -> Void)?
    var onChooseFolder: (() -> Void)?
    /// A folder picked from the path menu, or the parent button.
    var onNavigate: ((URL) -> Void)?

    private(set) var folder: URL?
    private var roots: [Node] = []

    private let title = NSTextField(labelWithString: "")
    private let upButton = NSButton()
    private let chooseButton = NSButton()
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let rule = NSBox()
    private var ink = NSColor.labelColor
    private var dimInk = NSColor.secondaryLabelColor
    private var ground = NSColor.textBackgroundColor
    private var textSize: CGFloat = 13

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func build() {
        setAccessibilityLabel("Files")
        title.lineBreakMode = .byTruncatingMiddle
        title.toolTip = "Choose a folder from the path"
        title.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(showPath(_:))))
        title.setAccessibilityRole(.button)
        title.setAccessibilityLabel("Folder path")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        upButton.bezelStyle = .accessoryBarAction
        upButton.isBordered = false
        upButton.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Parent Folder")
        upButton.toolTip = "Parent Folder"
        upButton.target = self
        upButton.action = #selector(goUp(_:))
        upButton.translatesAutoresizingMaskIntoConstraints = false

        chooseButton.bezelStyle = .accessoryBarAction
        chooseButton.isBordered = false
        chooseButton.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Choose Folder")
        chooseButton.toolTip = "Choose Folder"
        chooseButton.target = self
        chooseButton.action = #selector(chooseFolder(_:))
        chooseButton.translatesAutoresizingMaskIntoConstraints = false

        rule.boxType = .custom
        rule.borderWidth = 0
        rule.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.indentationPerLevel = 12
        outline.floatsGroupRows = false
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked(_:))
        outline.doubleAction = #selector(doubleClicked(_:))
        outline.setAccessibilityLabel("Files")

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, upButton, chooseButton, rule, scroll, emptyLabel] { addSubview(view) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: chooseButton.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: upButton.leadingAnchor, constant: -4),
            upButton.trailingAnchor.constraint(equalTo: chooseButton.leadingAnchor),
            upButton.centerYAnchor.constraint(equalTo: chooseButton.centerYAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 24),
            upButton.heightAnchor.constraint(equalToConstant: 24),
            chooseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chooseButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            chooseButton.widthAnchor.constraint(equalToConstant: 24),
            chooseButton.heightAnchor.constraint(equalToConstant: 24),
            rule.topAnchor.constraint(equalTo: chooseButton.bottomAnchor, constant: 6),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        showFolder(nil)
    }

    // MARK: Folder

    /// Shows `url`, or the empty state for nil. Keeps nothing of the old tree.
    func showFolder(_ url: URL?) {
        folder = url
        setTitle(url?.lastPathComponent ?? "Files")
        title.toolTip = url?.path
        upButton.isEnabled = url.map { $0.pathComponents.count > 1 } ?? false
        reload()
    }

    /// Lists the folder again, and keeps the folders that were open.
    func reload() {
        let open = openFolders()
        roots = folder.map { FolderListing.entries(in: $0).map(Node.init) } ?? []
        outline.reloadData()
        restore(open, in: roots)
        let empty = folder == nil || roots.isEmpty
        scroll.isHidden = empty
        emptyLabel.isHidden = !empty
        emptyLabel.stringValue = folder == nil
            ? "No folder yet. Choose one to list its Markdown files here."
            : "No Markdown files in this folder."
    }

    private func openFolders() -> Set<URL> {
        var open = Set<URL>()
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? Node, node.entry.isFolder, outline.isItemExpanded(node) {
                open.insert(node.entry.url)
            }
        }
        return open
    }

    private func restore(_ open: Set<URL>, in nodes: [Node]) {
        for node in nodes where node.entry.isFolder && open.contains(node.entry.url) {
            outline.expandItem(node)
            restore(open, in: children(of: node))
        }
    }

    private func children(of node: Node) -> [Node] {
        if let children = node.children { return children }
        let loaded = FolderListing.entries(in: node.entry.url).map(Node.init)
        node.children = loaded
        return loaded
    }

    /// Marks the row of `url`, opening its folders. Nothing happens if the file
    /// is not under the folder.
    func select(url: URL?) {
        guard let url, let folder else { return outline.deselectAll(nil) }
        let base = folder.standardizedFileURL.pathComponents
        let target = url.standardizedFileURL.pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else {
            return outline.deselectAll(nil)
        }
        var level = roots
        var path = folder.standardizedFileURL
        for component in target[base.count...] {
            path.appendPathComponent(component)
            guard let node = level.first(where: { $0.entry.url.standardizedFileURL == path }) else { return }
            if node.entry.isFolder {
                outline.expandItem(node)
                level = children(of: node)
            } else {
                let row = outline.row(forItem: node)
                if row >= 0 {
                    outline.selectRowIndexes([row], byExtendingSelection: false)
                    outline.scrollRowToVisible(row)
                }
            }
        }
    }

    private func setTitle(_ text: String) {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: ink,
        ])
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold)) {
            let attachment = NSTextAttachment()
            attachment.image = chevron.tinted(dimInk)
            result.append(NSAttributedString(string: "  "))
            result.append(NSAttributedString(attachment: attachment))
        }
        title.attributedStringValue = result
    }

    // MARK: Actions

    /// The folders above this one, nearest first, to the top of the disk.
    private var ancestors: [URL] {
        guard var url = folder?.standardizedFileURL else { return [] }
        var list: [URL] = []
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            list.append(url)
        }
        return list
    }

    @objc private func goUp(_ sender: Any?) {
        if let parent = ancestors.first { onNavigate?(parent) }
    }

    @objc private func showPath(_ sender: Any?) {
        let menu = NSMenu()
        if let folder {
            let current = NSMenuItem(title: folder.lastPathComponent, action: nil, keyEquivalent: "")
            current.state = .on
            menu.addItem(current)
        }
        for url in ancestors {
            let name = url.pathComponents.count == 1 ? (FileManager.default.displayName(atPath: url.path)) : url.lastPathComponent
            let item = NSMenuItem(title: name, action: #selector(pickAncestor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let choose = NSMenuItem(title: "Choose Folder…", action: #selector(chooseFolder(_:)), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: title.bounds.height + 2), in: title)
    }

    @objc private func pickAncestor(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onNavigate?(url) }
    }

    @objc private func chooseFolder(_ sender: Any?) { onChooseFolder?() }

    /// A double click on a folder makes it the folder of the sidebar.
    @objc private func doubleClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? Node, node.entry.isFolder else { return }
        onNavigate?(node.entry.url)
    }

    @objc private func clicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
        if node.entry.isFolder {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            onOpen?(node.entry.url)
        }
    }

    // MARK: Data

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return roots.count }
        return node.entry.isFolder ? children(of: node).count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? Node else { return roots[index] }
        return children(of: node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.entry.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        cell.textField?.stringValue = node.entry.name
        cell.textField?.font = .systemFont(ofSize: textSize)
        cell.textField?.textColor = node.entry.isFolder ? dimInk : ink
        cell.imageView?.image = NSImage(
            systemSymbolName: node.entry.isFolder ? "folder" : "doc.text",
            accessibilityDescription: nil
        )
        cell.imageView?.contentTintColor = dimInk
        cell.setAccessibilityLabel(node.entry.isFolder ? "\(node.entry.name), folder" : node.entry.name)
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        image.translatesAutoresizingMaskIntoConstraints = false
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.addSubview(text)
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 14),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: Theme

    func apply(palette: ResolvedPalette?) {
        appearance = palette.map { NSAppearance(named: $0.isDark ? .darkAqua : .aqua) } ?? nil
        ground = palette?.colors.background ?? .textBackgroundColor
        ink = palette?.colors.text ?? .labelColor
        dimInk = palette?.colors.textDim ?? .secondaryLabelColor
        outline.backgroundColor = ground
        scroll.backgroundColor = ground
        scroll.scrollerKnobStyle = palette.map { $0.isDark ? .light : .dark } ?? .default
        setTitle(folder?.lastPathComponent ?? "Files")
        upButton.contentTintColor = dimInk
        emptyLabel.textColor = dimInk
        chooseButton.contentTintColor = dimInk
        rule.fillColor = palette?.colors.borderColor ?? .separatorColor
        wantsLayer = true
        layer?.backgroundColor = ground.cgColor
        outline.reloadData()
    }

    // MARK: Testing

    var rowNamesForTesting: [String] {
        (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? Node)?.entry.name }
    }
    var selectedNameForTesting: String? {
        (outline.item(atRow: outline.selectedRow) as? Node)?.entry.name
    }
    func clickRowForTesting(named name: String) {
        for row in 0..<outline.numberOfRows where (outline.item(atRow: row) as? Node)?.entry.name == name {
            outline.selectRowIndexes([row], byExtendingSelection: false)
            guard let node = outline.item(atRow: row) as? Node else { return }
            if node.entry.isFolder { outline.expandItem(node) } else { onOpen?(node.entry.url) }
            return
        }
    }
}

private extension NSImage {
    /// The symbol drawn in one colour, for text attachments (they do not tint).
    func tinted(_ color: NSColor) -> NSImage {
        let copy = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        copy.isTemplate = false
        return copy
    }
}
