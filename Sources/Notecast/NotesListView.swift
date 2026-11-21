import AppKit
import Carbon.HIToolbox
import NotecastCore

/// In-window list of saved Markdown notes (`⌘L`), supporting keyboard navigation, switching, creation, and deletion.
@MainActor
final class NotesListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectNote: ((UUID) -> Void)?
    var onDeleteNote: ((UUID) -> Void)?
    var onNewNote: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var notes: [NoteMetadata] = []
    private var activeNoteID: UUID?
    private var surfaceStyle: SurfaceStyle = .immersiveBlack
    private var neonAccent: NeonAccent = .cyan

    private let countLabel = NSTextField(labelWithString: "Notes")
    private let newButton = NSButton(title: "+ New", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let separator = NSView()
    private let scrollView = NSScrollView()
    private let tableView = NotesTableView()

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        notes: [NoteMetadata],
        activeNoteID: UUID?,
        surfaceStyle: SurfaceStyle,
        neonAccent: NeonAccent
    ) {
        self.notes = notes
        self.activeNoteID = activeNoteID
        self.surfaceStyle = surfaceStyle
        self.neonAccent = neonAccent

        let noun = notes.count == 1 ? "note" : "notes"
        countLabel.stringValue = "\(notes.count) \(noun)"
        applySurfaceAppearance()
        tableView.reloadData()

        if let activeNoteID, let row = notes.firstIndex(where: { $0.id == activeNoteID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else if !notes.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func focusList() {
        window?.makeFirstResponder(tableView)
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor

        newButton.translatesAutoresizingMaskIntoConstraints = false
        newButton.bezelStyle = .rounded
        newButton.controlSize = .small
        newButton.toolTip = "New Note (⌘N)"
        newButton.target = self
        newButton.action = #selector(handleNewTapped)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.toolTip = "Back to Editor (Esc)"
        doneButton.target = self
        doneButton.action = #selector(handleDoneTapped)

        topBar.addSubview(countLabel)
        topBar.addSubview(newButton)
        topBar.addSubview(doneButton)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(handleRowClicked)

        tableView.onActivateSelected = { [weak self] in
            self?.openSelectedRow()
        }
        tableView.onCancel = { [weak self] in
            self?.onDismiss?()
        }
        tableView.onDeleteSelected = { [weak self] in
            self?.deleteSelectedRow()
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        addSubview(topBar)
        addSubview(separator)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 38),

            countLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            countLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -6),
            newButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            separator.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applySurfaceAppearance()
    }

    private func applySurfaceAppearance() {
        switch surfaceStyle {
        case .immersiveBlack:
            layer?.backgroundColor = NSColor.black.cgColor
            separator.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        case .translucentHUD:
            layer?.backgroundColor = NSColor.clear.cgColor
            separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
    }

    // MARK: - NSTableViewDataSource & NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        notes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < notes.count else { return nil }
        let note = notes[row]
        let isActive = note.id == activeNoteID

        let identifier = NSUserInterfaceItemIdentifier("NoteRowCell")
        let cell: NoteRowCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NoteRowCellView {
            cell = reused
        } else {
            cell = NoteRowCellView()
            cell.identifier = identifier
        }

        let timestamp = Self.formatTimestamp(note.updatedAt, formatter: relativeFormatter)
        cell.configure(
            note: note,
            timestamp: timestamp,
            isActive: isActive,
            accentColor: neonAccent.nsColor
        ) { [weak self] noteID in
            self?.onDeleteNote?(noteID)
        }
        return cell
    }

    // MARK: - Actions

    @objc private func handleNewTapped() {
        onNewNote?()
    }

    @objc private func handleDoneTapped() {
        onDismiss?()
    }

    @objc private func handleRowClicked() {
        openSelectedRow()
    }

    private func openSelectedRow() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < notes.count else { return }
        onSelectNote?(notes[row].id)
    }

    private func deleteSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < notes.count else { return }
        onDeleteNote?(notes[row].id)
    }

    private static func formatTimestamp(_ date: Date, formatter: RelativeDateTimeFormatter) -> String {
        if abs(date.timeIntervalSinceNow) < 45 {
            return "just now"
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private final class NotesTableView: NSTableView {
    var onActivateSelected: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDeleteSelected: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            onActivateSelected?()
            return
        }
        if keyCode == kVK_Escape {
            onCancel?()
            return
        }
        if keyCode == kVK_Delete && modifiers == [.command] {
            onDeleteSelected?()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
private final class NoteRowCellView: NSTableCellView {
    private let dotView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()

    private var noteID: UUID?
    private var onDelete: ((UUID) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCell()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        note: NoteMetadata,
        timestamp: String,
        isActive: Bool,
        accentColor: NSColor,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.noteID = note.id
        self.onDelete = onDelete

        titleLabel.stringValue = note.title
        previewLabel.stringValue = note.preview.isEmpty ? "Empty note" : note.preview
        timeLabel.stringValue = timestamp

        dotView.isHidden = !isActive
        dotView.layer?.backgroundColor = accentColor.cgColor
    }

    private func setupCell() {
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.alignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isBordered = false
        deleteButton.bezelStyle = .regularSquare
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Note")
        deleteButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.toolTip = "Delete Note"
        deleteButton.target = self
        deleteButton.action = #selector(handleDeleteTapped)

        addSubview(dotView)
        addSubview(titleLabel)
        addSubview(previewLabel)
        addSubview(timeLabel)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dotView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 25),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),

            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
        ])
    }

    @objc private func handleDeleteTapped() {
        guard let noteID else { return }
        onDelete?(noteID)
    }
}
