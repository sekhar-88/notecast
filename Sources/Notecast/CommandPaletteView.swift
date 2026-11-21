import AppKit
import NotecastCore

/// Raycast-style inline modal search & command palette overlay (`⌘P`).
@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var queryProvider: ((String) -> [PaletteEntry])?
    var onSelectEntry: ((PaletteEntry) -> Void)?
    var onDismiss: (() -> Void)?

    private var entries: [PaletteEntry] = []
    private var surfaceStyle: SurfaceStyle = .immersiveBlack
    private var neonGlowEnabled = true
    private var neonAccent: NeonAccent = .cyan

    private let cardView = NSView()
    private let searchIcon = NSImageView()
    private let searchField = NSTextField()
    private let divider = NSView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No matching notes or commands")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func openPalette(
        surfaceStyle: SurfaceStyle,
        neonGlowEnabled: Bool,
        neonAccent: NeonAccent
    ) {
        self.surfaceStyle = surfaceStyle
        self.neonGlowEnabled = neonGlowEnabled
        self.neonAccent = neonAccent

        searchField.stringValue = ""
        reloadResults()
        applyTheme()
        window?.makeFirstResponder(searchField)
    }

    func applyTheme(
        surfaceStyle: SurfaceStyle,
        neonGlowEnabled: Bool,
        neonAccent: NeonAccent
    ) {
        self.surfaceStyle = surfaceStyle
        self.neonGlowEnabled = neonGlowEnabled
        self.neonAccent = neonAccent
        applyTheme()
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if !cardView.frame.contains(localPoint) {
            onDismiss?()
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 10
        cardView.layer?.masksToBounds = true
        cardView.layer?.borderWidth = 1

        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        searchIcon.contentTintColor = .secondaryLabelColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        searchField.placeholderString = "Search notes or type > for commands…"
        searchField.delegate = self

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PaletteColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 40
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(handleRowClicked)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        addSubview(cardView)
        cardView.addSubview(searchIcon)
        cardView.addSubview(searchField)
        cardView.addSubview(divider)
        cardView.addSubview(scrollView)
        cardView.addSubview(emptyLabel)

        let preferredWidth = cardView.widthAnchor.constraint(equalToConstant: 368)
        preferredWidth.priority = .defaultHigh

        let preferredHeight = scrollView.heightAnchor.constraint(equalToConstant: 250)
        preferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            preferredWidth,

            searchIcon.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            searchIcon.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),

            divider.topAnchor.constraint(equalTo: searchIcon.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            preferredHeight,

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        applyTheme()
    }

    private func applyTheme() {
        switch surfaceStyle {
        case .immersiveBlack:
            cardView.layer?.backgroundColor = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.063, alpha: 0.98).cgColor
            divider.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        case .translucentHUD:
            cardView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
            divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }

        if neonGlowEnabled {
            cardView.layer?.borderColor = neonAccent.nsColor.withAlphaComponent(0.65).cgColor
            searchIcon.contentTintColor = neonAccent.nsColor
        } else {
            cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            searchIcon.contentTintColor = .secondaryLabelColor
        }
    }

    private func reloadResults() {
        entries = queryProvider?(searchField.stringValue) ?? []
        emptyLabel.isHidden = !entries.isEmpty
        tableView.reloadData()
        if !entries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        reloadResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(delta: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(delta: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelectedEntry()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
            return true
        default:
            return false
        }
    }

    // MARK: - NSTableViewDataSource & NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < entries.count else { return nil }
        let entry = entries[row]

        let identifier = NSUserInterfaceItemIdentifier("PaletteRowCell")
        let cell: PaletteRowCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? PaletteRowCellView {
            cell = reused
        } else {
            cell = PaletteRowCellView()
            cell.identifier = identifier
        }

        cell.configure(entry: entry, accentColor: neonGlowEnabled ? neonAccent.nsColor : .secondaryLabelColor)
        return cell
    }

    @objc private func handleRowClicked() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        onSelectEntry?(entries[row])
    }

    private func moveSelection(delta: Int) {
        guard !entries.isEmpty else { return }
        let current = tableView.selectedRow
        let next: Int
        if current < 0 {
            next = 0
        } else {
            next = (current + delta + entries.count) % entries.count
        }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func activateSelectedEntry() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        onSelectEntry?(entries[row])
    }
}

@MainActor
private final class PaletteRowCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCell()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(entry: PaletteEntry, accentColor: NSColor) {
        switch entry {
        case .note(let note):
            iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            iconView.contentTintColor = accentColor
            titleLabel.stringValue = note.title
            subtitleLabel.stringValue = note.preview.isEmpty ? "Note" : note.preview
            shortcutLabel.stringValue = "Note"
        case .command(let command):
            iconView.image = NSImage(systemSymbolName: command.symbolName, accessibilityDescription: nil)
            iconView.contentTintColor = .secondaryLabelColor
            titleLabel.stringValue = command.title
            subtitleLabel.stringValue = command.subtitle
            shortcutLabel.stringValue = command.shortcut
        }
    }

    private func setupCell() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -5),

            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }
}
