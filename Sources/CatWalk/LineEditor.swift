import AppKit

/// A small window for editing what the cats say, so nobody has to touch
/// 대사.txt by hand. Every change saves and applies immediately.
final class LineEditor: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let shared = LineEditor()

    private let segments = NSSegmentedControl(
        labels: [CustomLines.caringSection, CustomLines.cattySection, CustomLines.pinnedSection],
        trackingMode: .selectOne, target: nil, action: nil
    )
    private let tableView = NSTableView()
    private let hint = NSTextField(labelWithString: "")

    /// One line pool per segment, in the same order as `segments`.
    private var pools: [[String]] = [[], [], []]
    private var current: Int { max(segments.selectedSegment, 0) }

    private static let hints = [
        "고양이를 클릭하거나, 돌아다니다가 혼자 하는 말이에요.",
        "가끔씩 섞여 나오는 고양이 소리예요.",
        "드래그해서 자리에 고정했을 때 하는 말이에요.",
    ]

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "대사 편집"
        window.minSize = NSSize(width: 280, height: 300)
        self.init(window: window)
        buildUI()
    }

    func show() {
        pools = [CatLines.caring, CatLines.catty, CatLines.pinned]
        tableView.reloadData()
        updateHint()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        segments.selectedSegment = 0
        segments.target = self
        segments.action = #selector(sectionChanged)

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("line"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        let add = NSButton(image: NSImage(named: NSImage.addTemplateName)!,
                           target: self, action: #selector(addLine))
        let remove = NSButton(image: NSImage(named: NSImage.removeTemplateName)!,
                              target: self, action: #selector(removeLines))
        add.bezelStyle = .smallSquare
        remove.bezelStyle = .smallSquare

        let buttons = NSStackView(views: [add, remove])
        buttons.orientation = .horizontal
        buttons.spacing = 0

        let editHint = NSTextField(labelWithString: "더블클릭해서 수정 · 저장은 자동이에요")
        editHint.font = .systemFont(ofSize: 11)
        editHint.textColor = .tertiaryLabelColor

        let bottom = NSStackView(views: [buttons, editHint])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY

        let stack = NSStackView(views: [segments, hint, scroll, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            segments.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            hint.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    private func updateHint() {
        hint.stringValue = LineEditor.hints[current]
    }

    // MARK: - Actions

    @objc private func sectionChanged() {
        tableView.reloadData()
        updateHint()
    }

    @objc private func addLine() {
        pools[current].append("")
        tableView.reloadData()
        let row = pools[current].count - 1
        tableView.scrollRowToVisible(row)
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeLines() {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return }
        pools[current] = pools[current].enumerated()
            .filter { !rows.contains($0.offset) }
            .map(\.element)
        tableView.reloadData()
        save()
    }

    private func save() {
        CustomLines.save(caring: pools[0], catty: pools[1], pinned: pools[2])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        pools[current].count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField()
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = pools[current][row]
        return cell
    }

    /// Commits an edit when the field loses focus; an emptied line is removed.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard row >= 0, row < pools[current].count else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            pools[current].remove(at: row)
            tableView.reloadData()
        } else {
            pools[current][row] = text
        }
        save()
    }
}
