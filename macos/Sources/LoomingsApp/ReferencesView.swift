import AppKit
import LoomingsCitations
import LoomingsTheme

/// The library of a document, in the right column of Split: a filter field and
/// a table. All text is plain, in text fields. The rows come from
/// `ReferenceList`, and the window applies the insertion.
@MainActor
final class ReferencesView: NSView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("reference")
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("reference-row")
    private static let maximumWidth: CGFloat = 720
    private static let filterLabel = "Filter the library"

    /// Inserts this key.
    var onInsert: ((String) -> Void)?
    /// Gives the focus back to the editor.
    var onLeave: (() -> Void)?

    let filterField = NSSearchField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let tableView = ReferencesTableView()
    private let tableScroll = NSScrollView()
    /// A message can stand above the rows: cited keys with no library.
    private var tableUnderField: NSLayoutConstraint!
    private var tableUnderStatus: NSLayoutConstraint!

    private var shownReport: CitationReport?
    private var list = ReferenceList(report: nil)
    private var rows: [ReferenceRow] = []
    private var waiting = false
    private var ground: NSColor = .textBackgroundColor
    private var style = ReferenceCellStyle(palette: nil, textSize: 13)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        filterField.delegate = self
        filterField.target = self
        filterField.action = #selector(filterChanged(_:))
        filterField.sendsSearchStringImmediately = true
        filterField.sendsWholeSearchString = false
        filterField.centersPlaceholder = false
        filterField.setAccessibilityLabel(Self.filterLabel)

        status.isSelectable = false
        status.font = NSFont.systemFont(ofSize: 13)

        let column = NSTableColumn(identifier: Self.cellIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.setAccessibilityLabel("Library")
        tableView.onActivate = { [weak self] in self?.insertSelection() }
        tableView.onCancel = { [weak self] in self?.onLeave?() }

        tableScroll.documentView = tableView
        tableScroll.verticalScroller = ThemedScroller()
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = false
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .noBorder
        tableScroll.drawsBackground = true

        filterField.nextKeyView = tableView
        tableView.nextKeyView = filterField

        // Each width stays below the split view's holding priority (250).
        // Above it, a wish moves the divider, and above 500 the window.
        let content = NSLayoutGuide()
        addLayoutGuide(content)
        for view in [filterField, status, tableScroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // A wide window gives this view much room: the rows keep a measure.
        let measure = content.widthAnchor.constraint(equalToConstant: Self.maximumWidth)
        measure.priority = NSLayoutConstraint.Priority(100)
        let margin = content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24)
        margin.priority = NSLayoutConstraint.Priority(200)
        for view in [filterField, status] {
            view.setContentHuggingPriority(NSLayoutConstraint.Priority(50), for: .horizontal)
            view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(50), for: .horizontal)
        }
        tableUnderField = tableScroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8)
        tableUnderStatus = tableScroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            margin,
            measure,
            filterField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            filterField.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            filterField.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            status.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tableScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        show()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReferencesView is created in code")
    }

    /// The field keeps the place of its icon from a layout in a hidden column,
    /// which has no width.
    override func viewDidUnhide() {
        super.viewDidUnhide()
        (filterField.cell as? NSSearchFieldCell)?.resetSearchButtonCell()
        filterField.needsDisplay = true
    }

    /// `bounds`, not `dirtyRect`: since macOS 14 a view does not clip, and the
    /// dirty rectangle can reach over the control above this view.
    override func draw(_ dirtyRect: NSRect) {
        ground.setFill()
        bounds.fill()
    }

    // MARK: Content

    /// Shows this report. The filter and the selected key stay.
    /// - Parameter waiting: a report for this document is on its way.
    func update(report: CitationReport?, waiting: Bool) {
        // The window asks after each parse, and the folds of a long library cost.
        guard report != shownReport || waiting != self.waiting else { return }
        shownReport = report
        list = ReferenceList(report: report)
        self.waiting = waiting
        show()
    }

    private func show() {
        let selected = selectedKey
        let next = list.rows(filter: filterField.stringValue)
        if next != rows {
            rows = next
            tableView.reloadData()
        }
        select(key: selected)
        updateMessage()
    }

    private func updateMessage() {
        let message: String
        if rows.isEmpty, !list.isEmpty {
            message = "No entry matches."
        } else if list.hasNoEntries {
            message = waiting
                ? "Reading the references\u{2026}"
                : "No references yet. Choose a .bib file with Choose Bibliography\u{2026} in the References menu."
        } else {
            message = ""
        }
        if message != status.stringValue, !message.isEmpty {
            NSAccessibility.post(element: status, notification: .announcementRequested, userInfo: [
                .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
        status.stringValue = message
        status.isHidden = message.isEmpty
        filterField.isHidden = list.isEmpty
        tableScroll.isHidden = rows.isEmpty
        tableUnderField.isActive = status.isHidden
        tableUnderStatus.isActive = !status.isHidden
    }

    private var selectedKey: String? {
        rows.indices.contains(tableView.selectedRow) ? rows[tableView.selectedRow].key : nil
    }

    private func select(key: String?) {
        let index = key.flatMap { key in rows.firstIndex { $0.key == key } }
        if let index {
            if tableView.selectedRow != index {
                tableView.selectRowIndexes([index], byExtendingSelection: false)
            }
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
    }

    // MARK: Input

    @objc private func filterChanged(_ sender: Any?) {
        let selected = selectedKey
        rows = list.rows(filter: filterField.stringValue)
        tableView.reloadData()
        // With a filter, Return takes the first entry, and the row shows it.
        // With no filter and no selection, Return has nothing to insert.
        select(key: selected ?? (filterField.stringValue.isEmpty ? nil : firstEntry?.key))
        updateMessage()
    }

    private var firstEntry: ReferenceRow? { rows.first { !$0.isMissing } }

    @objc private func doubleClicked(_ sender: Any?) {
        guard rows.indices.contains(tableView.clickedRow) else { return }
        insert(rows[tableView.clickedRow])
    }

    private func insertSelection() {
        if rows.indices.contains(tableView.selectedRow) {
            insert(rows[tableView.selectedRow])
        } else if !filterField.stringValue.isEmpty, let firstEntry {
            insert(firstEntry)
        }
    }

    /// A key with no entry is a fault to mend, not a choice.
    private func insert(_ row: ReferenceRow) {
        guard !row.isMissing else { return }
        onInsert?(row.key)
    }

    /// The arrow keys move through the rows while the focus stays in the field.
    private func moveSelection(by step: Int) {
        var index = tableView.selectedRow < 0 ? (step > 0 ? -1 : rows.count) : tableView.selectedRow
        repeat {
            index += step
        } while rows.indices.contains(index) && rows[index].isMissing
        guard rows.indices.contains(index) else { return }
        tableView.selectRowIndexes([index], byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            insertSelection()
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.cancelOperation(_:)):
            if filterField.stringValue.isEmpty {
                onLeave?()
            } else {
                filterField.stringValue = ""
                filterChanged(nil)
            }
        default:
            return false
        }
        return true
    }

    // MARK: Theme

    /// - Parameter textSize: the size of the body text. Projector mode gives a bigger one.
    func apply(palette: ResolvedPalette?, textSize: CGFloat) {
        appearance = palette.map { NSAppearance(named: $0.isDark ? .darkAqua : .aqua) } ?? nil
        ground = palette?.colors.background ?? .textBackgroundColor
        let next = ReferenceCellStyle(palette: palette, textSize: textSize)
        let changed = next != style
        style = next
        needsDisplay = true

        tableView.backgroundColor = ground
        tableScroll.backgroundColor = ground
        tableScroll.scrollerKnobStyle = palette.map { $0.isDark ? .light : .dark } ?? .default
        (tableScroll.verticalScroller as? ThemedScroller)?.trackColor = palette?.colors.background

        filterField.font = NSFont.systemFont(ofSize: textSize)
        filterField.textColor = palette?.colors.text ?? .labelColor
        filterField.placeholderAttributedString = NSAttributedString(
            string: Self.filterLabel,
            attributes: [
                .font: NSFont.systemFont(ofSize: textSize),
                .foregroundColor: style.dimInk,
            ]
        )
        status.font = NSFont.systemFont(ofSize: textSize)
        status.textColor = style.dimInk
        if changed { tableView.reloadData() }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows.indices.contains(row) && !rows[row].isMissing
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 1 }
        return style.height(of: rows[row])
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: Self.rowIdentifier, owner: nil) as? ReferenceRowView ?? ReferenceRowView()
        view.identifier = Self.rowIdentifier
        view.selectionFill = style.selection
        view.rule = style.rule
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil) as? ReferenceCellView ?? ReferenceCellView()
        cell.identifier = Self.cellIdentifier
        cell.show(rows[row], style: style)
        return cell
    }

    // MARK: Testing

    var rowsForTesting: [ReferenceRow] { rows }
    var messageForTesting: String? { status.isHidden ? nil : status.stringValue }
    var tableForTesting: NSTableView { tableView }
    /// True when the message and the rows do not overlap.
    var messageClearsRowsForTesting: Bool { !status.frame.intersects(tableScroll.frame) }
    var tableBackgroundForTesting: NSColor { tableView.backgroundColor }
    var rowHeightForTesting: CGFloat { rows.first.map(style.height(of:)) ?? 0 }

    func filterForTesting(_ text: String) {
        filterField.stringValue = text
        filterChanged(nil)
    }

    func selectForTesting(key: String?) {
        select(key: key)
    }

    func cellForTesting(row: Int) -> NSView? {
        tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
    }
}

/// Return and Escape on the table.
private final class ReferencesTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onActivate?()
        case 53: onCancel?()
        default: super.keyDown(with: event)
        }
    }
}

/// The fonts and colours of one row.
private struct ReferenceCellStyle: Equatable {
    let keyFont: NSFont
    let markFont: NSFont
    let textFont: NSFont
    let ink: NSColor
    let dimInk: NSColor
    let missingInk: NSColor
    let selection: NSColor
    let rule: NSColor
    private let keyLine: CGFloat
    private let textLine: CGFloat

    static let padding: CGFloat = 8

    @MainActor
    init(palette: ResolvedPalette?, textSize: CGFloat) {
        keyFont = NSFont(name: "JetBrainsMono-Regular", size: textSize * 0.92)
            ?? .monospacedSystemFont(ofSize: textSize * 0.92, weight: .regular)
        markFont = .systemFont(ofSize: textSize * 0.85)
        textFont = .systemFont(ofSize: textSize)
        ink = palette?.colors.text ?? .labelColor
        dimInk = palette?.colors.textDim ?? .secondaryLabelColor
        missingInk = palette?.colors.linkColor ?? .linkColor
        selection = palette?.colors.selectionColor ?? .selectedContentBackgroundColor
        rule = palette?.colors.borderColor ?? .separatorColor
        let layout = NSLayoutManager()
        keyLine = layout.defaultLineHeight(for: keyFont).rounded(.up)
        textLine = layout.defaultLineHeight(for: textFont).rounded(.up)
    }

    /// The key line, then a line for each part that the row has. The table
    /// asks for each row, so the line heights come from `init`.
    func height(of row: ReferenceRow) -> CGFloat {
        let lines = (row.byline.isEmpty ? 0 : 1) + (row.title.isEmpty ? 0 : 1)
        return keyLine + CGFloat(lines) * (textLine + 1) + Self.padding * 2 + 1
    }
}

/// One row: the key and its mark, then the byline, then the title. VoiceOver
/// reads the row as one element.
private final class ReferenceCellView: NSTableCellView {
    private let key = NSTextField(labelWithString: "")
    private let mark = NSTextField(labelWithString: "")
    private let byline = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private var titleUnderKey: NSLayoutConstraint!
    private var titleUnderByline: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        for label in [key, mark, byline, title] {
            label.setAccessibilityElement(false)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        mark.setContentCompressionResistancePriority(.required, for: .horizontal)
        mark.setContentHuggingPriority(.required, for: .horizontal)

        let padding = ReferenceCellStyle.padding
        for label in [key, mark, byline, title] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        titleUnderKey = title.topAnchor.constraint(equalTo: key.bottomAnchor, constant: 1)
        titleUnderByline = title.topAnchor.constraint(equalTo: byline.bottomAnchor, constant: 1)
        NSLayoutConstraint.activate([
            key.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            key.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            mark.firstBaselineAnchor.constraint(equalTo: key.firstBaselineAnchor),
            mark.leadingAnchor.constraint(greaterThanOrEqualTo: key.trailingAnchor, constant: 10),
            mark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            byline.topAnchor.constraint(equalTo: key.bottomAnchor, constant: 1),
            byline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            byline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReferenceCellView is created in code")
    }

    func show(_ row: ReferenceRow, style: ReferenceCellStyle) {
        key.stringValue = row.key
        byline.stringValue = row.byline
        title.stringValue = row.title
        mark.stringValue = row.isMissing ? "cited, no entry" : (row.isCited ? "cited" : "")
        byline.isHidden = row.byline.isEmpty
        title.isHidden = row.title.isEmpty
        titleUnderKey.isActive = byline.isHidden
        titleUnderByline.isActive = !byline.isHidden
        mark.isHidden = mark.stringValue.isEmpty
        toolTip = row.title.isEmpty ? nil : row.title

        key.font = style.keyFont
        key.textColor = style.ink
        mark.font = style.markFont
        mark.textColor = row.isMissing ? style.missingInk : style.dimInk
        byline.font = style.textFont
        byline.textColor = style.dimInk
        title.font = style.textFont
        title.textColor = style.ink

        setAccessibilityLabel([row.key, mark.stringValue, row.byline, row.title].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// The selection takes the palette's role, and a hairline parts the rows.
private final class ReferenceRowView: NSTableRowView {
    var selectionFill: NSColor = .selectedContentBackgroundColor
    var rule: NSColor = .separatorColor

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        selectionFill.setFill()
        bounds.fill()
    }

    override func drawSeparator(in dirtyRect: NSRect) {}

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        rule.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
