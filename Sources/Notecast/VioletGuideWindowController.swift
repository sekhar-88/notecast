import AppKit
import Carbon.HIToolbox
import NotecastCore

/// Floating amethyst-violet card presenting either a concise first-install Quick Start or expanded Instructions & Shortcuts.
@MainActor
final class VioletGuideWindowController: NSWindowController, NSWindowDelegate {
    enum Mode: Equatable {
        case welcome
        case instructions

        var windowSize: NSSize {
            switch self {
            case .welcome:
                return NSSize(width: 386, height: 424)
            case .instructions:
                return NSSize(width: 484, height: 576)
            }
        }
    }

    var onOpenSettings: (() -> Void)?
    var onDismissToEditor: (() -> Void)?
    var onDidClose: (() -> Void)?

    private(set) var currentMode: Mode
    private var lastAvoidingPanelFrame: NSRect?

    private let cardView = VioletCardView()
    private let headerView = GuideDragHeaderView()
    private let headerIconView = NSImageView()
    private let headerTitleLabel = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let headerDivider = NSView()
    private let bodyContainer = NSView()
    private let footerDivider = NSView()
    private let secondaryButton = NSButton()
    private let primaryButton = NSButton()

    private let violetAccent = NSColor(srgbRed: 0xB8 / 255.0, green: 0x4D / 255.0, blue: 1.0, alpha: 1.0)
    private let softVioletText = NSColor(srgbRed: 0xD8 / 255.0, green: 0xCC / 255.0, blue: 0xF5 / 255.0, alpha: 0.90)
    private let primaryText = NSColor(srgbRed: 0xF6 / 255.0, green: 0xF2 / 255.0, blue: 1.0, alpha: 0.97)

    init(mode: Mode = .welcome) {
        self.currentMode = mode
        let size = mode.windowSize
        let panel = GuidePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        panel.delegate = self

        panel.onEscapeOrClose = { [weak self] in
            self?.dismissGuide()
        }
        panel.onOpenSettingsShortcut = { [weak self] in
            self?.onOpenSettings?()
        }

        buildChrome()
        renderMode(mode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(mode: Mode, avoiding panelFrame: NSRect? = nil) {
        if let panelFrame {
            lastAvoidingPanelFrame = panelFrame
        }
        renderMode(mode)
        if let window {
            let size = mode.windowSize
            window.setContentSize(size)
            window.layoutIfNeeded()

            if let panelFrame {
                let screen = NSScreen.screens.first { $0.frame.intersects(panelFrame) }
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
                if let visibleFrame = screen?.visibleFrame {
                    let origin = WindowFrameClamper.settingsOrigin(
                        for: size,
                        avoiding: panelFrame,
                        in: visibleFrame
                    )
                    window.setFrameOrigin(origin)
                } else {
                    window.center()
                }
            } else {
                window.center()
            }

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Chrome & Layout

    private func buildChrome() {
        guard let contentView = window?.contentView else { return }

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.imageScaling = .scaleProportionallyUpOrDown
        headerIconView.image = NotecastBrandIcon.headerIconImage(
            size: NSSize(width: 22, height: 22),
            accentColor: violetAccent,
            isActive: true
        )

        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerTitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        headerTitleLabel.textColor = primaryText

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.backgroundColor = violetAccent.withAlphaComponent(0.18).cgColor
        badgeContainer.layer?.borderColor = violetAccent.withAlphaComponent(0.45).cgColor
        badgeContainer.layer?.borderWidth = 1
        badgeContainer.layer?.cornerRadius = 9
        badgeContainer.layer?.cornerCurve = .continuous

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        badgeLabel.textColor = NSColor(srgbRed: 0xE2 / 255.0, green: 0xB8 / 255.0, blue: 1.0, alpha: 1.0)
        badgeContainer.addSubview(badgeLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        closeButton.contentTintColor = softVioletText.withAlphaComponent(0.72)
        closeButton.target = self
        closeButton.action = #selector(handleDismissClicked)

        headerView.addSubview(headerIconView)
        headerView.addSubview(headerTitleLabel)
        headerView.addSubview(badgeContainer)
        headerView.addSubview(closeButton)

        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.wantsLayer = true
        headerDivider.layer?.backgroundColor = violetAccent.withAlphaComponent(0.24).cgColor

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = violetAccent.withAlphaComponent(0.20).cgColor

        configureButton(secondaryButton, isPrimary: false)
        secondaryButton.target = self
        secondaryButton.action = #selector(handleSecondaryClicked)

        configureButton(primaryButton, isPrimary: true)
        primaryButton.target = self
        primaryButton.action = #selector(handlePrimaryClicked)

        cardView.addSubview(headerView)
        cardView.addSubview(headerDivider)
        cardView.addSubview(bodyContainer)
        cardView.addSubview(footerDivider)
        cardView.addSubview(secondaryButton)
        cardView.addSubview(primaryButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            headerView.topAnchor.constraint(equalTo: cardView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 48),

            headerIconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            headerIconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            headerIconView.widthAnchor.constraint(equalToConstant: 22),
            headerIconView.heightAnchor.constraint(equalToConstant: 22),

            headerTitleLabel.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 9),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            badgeContainer.leadingAnchor.constraint(equalTo: headerTitleLabel.trailingAnchor, constant: 8),
            badgeContainer.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 2.5),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor, constant: -2.5),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 8),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -8),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            headerDivider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            headerDivider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            bodyContainer.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 12),
            bodyContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            bodyContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            bodyContainer.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -12),

            footerDivider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            footerDivider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            footerDivider.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -12),
            footerDivider.heightAnchor.constraint(equalToConstant: 1),

            secondaryButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            secondaryButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            secondaryButton.heightAnchor.constraint(equalToConstant: 30),

            primaryButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            primaryButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
            primaryButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func renderMode(_ mode: Mode) {
        currentMode = mode
        bodyContainer.subviews.forEach { $0.removeFromSuperview() }

        switch mode {
        case .welcome:
            headerTitleLabel.stringValue = "Welcome to Notecast"
            badgeLabel.stringValue = "Quick Start"
            setButtonTitle("Full Guide →", on: secondaryButton, isPrimary: false)
            setButtonTitle("Start Writing", on: primaryButton, isPrimary: true)
            buildWelcomeBody(in: bodyContainer)
        case .instructions:
            headerTitleLabel.stringValue = "Notecast Guide"
            badgeLabel.stringValue = "Instructions & Shortcuts"
            setButtonTitle("Open Settings (⌘,)", on: secondaryButton, isPrimary: false)
            setButtonTitle("Done", on: primaryButton, isPrimary: true)
            buildInstructionsBody(in: bodyContainer)
        }
    }

    private func buildWelcomeBody(in container: NSView) {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9

        let features: [(symbol: String, title: String, detail: String)] = [
            (
                "bolt.fill",
                "Instant Summon (⌥⌘N)",
                "Pop open or hide Notecast from any app or full-screen Space."
            ),
            (
                "magnifyingglass",
                "Quick Notes & Search (⌘P · ⌘⇧P · ⌘N · ⌘L)",
                "Command palette, notes search, new notes, and note switcher."
            ),
            (
                "rectangle.dashed",
                "Ghost Outline Mode",
                "Click-through outline when unfocused; click the right edge to wake or hold & drag it to move."
            ),
            (
                "slider.horizontal.3",
                "Settings (⌘, · Global ⌥⌘,)",
                "12 backgrounds, live font preview, neon accents, and adjustable wake zone."
            )
        ]

        for feature in features {
            let card = makeFrostedCard()
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.image = NSImage(systemSymbolName: feature.symbol, accessibilityDescription: nil)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
            icon.contentTintColor = violetAccent

            let titleField = NSTextField(labelWithString: feature.title)
            titleField.translatesAutoresizingMaskIntoConstraints = false
            titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            titleField.textColor = primaryText

            let detailField = NSTextField(wrappingLabelWithString: feature.detail)
            detailField.translatesAutoresizingMaskIntoConstraints = false
            detailField.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            detailField.textColor = softVioletText

            card.addSubview(icon)
            card.addSubview(titleField)
            card.addSubview(detailField)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),

                titleField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
                titleField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                titleField.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),

                detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                detailField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
                detailField.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9)
            ])

            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
    }

    private func buildInstructionsBody(in container: NSView) {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let documentView = FlippedContainerView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        stack.addArrangedSubview(makeShortcutSection(
            heading: "Shortcuts",
            rows: [
                ("⌥⌘N", "Toggle Notecast globally (any app or Space)"),
                ("⌥⌘,  /  ⌘,", "Open Preferences globally or in-app"),
                ("⌘P", "Search notes & commands (type > for commands only)"),
                ("⌘⇧P", "Search notes only"),
                ("⌘N / ⌘L", "Create new note / Toggle Notes List"),
                ("⌘+ / ⌘− / ⌘0", "Zoom editor text size or reset to 14 pt"),
                ("⌘? / Esc", "Open this guide / Dismiss overlay or palette")
            ],
            parentStack: stack
        ))

        stack.addArrangedSubview(makeBulletSection(
            heading: "Markdown & Smart Editing",
            items: [
                "# Headings (# to ####), > quotes, and ``` fenced blocks style live as you type.",
                "Inline formatting: **bold** (⌘B), *italic* (⌘I), `code` (⌘E), and ~~strikethrough~~ (⌘⇧X).",
                "Checklists & lists: ⌘⇧L or ⌘↩ toggles tasks, clicking [ ] flips checkboxes, Enter continues or exits lists, and Tab / ⇧Tab indents or outdents.",
                "Paste (⌘V) always strips rich formatting to keep scratchpad notes clean plain text."
            ],
            parentStack: stack
        ))

        stack.addArrangedSubview(makeBulletSection(
            heading: "Ghost Outline Mode & Drag Handle",
            items: [
                "Enable \"Transparent outline when unfocused\" in Settings (⌘,).",
                "When unfocused, only the top/bottom dotted bars, corner brackets, and right handle stay visible — the left area is click-through.",
                "Normal click the right handle area to wake Notecast and resume typing.",
                "Hold & drag the right handle area to reposition the ghosted outline without waking the notes.",
                "Adjust Ghost Wake Area (15%–100%) in Settings; if dragged near a screen edge, Notecast auto-adjusts so the handle never gets stuck off-screen."
            ],
            parentStack: stack
        ))

        stack.addArrangedSubview(makeBulletSection(
            heading: "Appearance & Local Storage",
            items: [
                "Choose from 12 visual background themes (dark charcoal/slate, light paper/mist, or frosted HUD) directly in Settings.",
                "Pick from 5 active neon border accents and preview installed fonts live with ↑ / ↓ arrow keys.",
                "Notes save automatically and atomically as Markdown files in ~/Library/Application Support/Notecast/notes/."
            ],
            parentStack: stack
        ))

        documentView.addSubview(stack)
        scrollView.documentView = documentView
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -4)
        ])
    }

    // MARK: - Section Builders

    private func makeShortcutSection(
        heading: String,
        rows: [(keys: String, desc: String)],
        parentStack: NSStackView
    ) -> NSView {
        let card = makeFrostedCard()
        let inner = NSStackView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6

        inner.addArrangedSubview(makeSectionHeading(heading))

        for row in rows {
            let line = NSStackView()
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 8

            let pill = makeKeycapPill(row.keys)
            let desc = NSTextField(wrappingLabelWithString: row.desc)
            desc.font = NSFont.systemFont(ofSize: 11.5)
            desc.textColor = softVioletText

            line.addArrangedSubview(pill)
            line.addArrangedSubview(desc)
            inner.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }

        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            card.widthAnchor.constraint(equalTo: parentStack.widthAnchor)
        ])
        return card
    }

    private func makeBulletSection(
        heading: String,
        items: [String],
        parentStack: NSStackView
    ) -> NSView {
        let card = makeFrostedCard()
        let inner = NSStackView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 5

        inner.addArrangedSubview(makeSectionHeading(heading))

        for item in items {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 6

            let dot = NSTextField(labelWithString: "•")
            dot.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
            dot.textColor = violetAccent
            dot.setContentHuggingPriority(.required, for: .horizontal)

            let label = NSTextField(wrappingLabelWithString: item)
            label.font = NSFont.systemFont(ofSize: 11.5)
            label.textColor = softVioletText

            row.addArrangedSubview(dot)
            row.addArrangedSubview(label)
            inner.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }

        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            card.widthAnchor.constraint(equalTo: parentStack.widthAnchor)
        ])
        return card
    }

    private func makeFrostedCard() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, alpha: 0.10).cgColor
        card.layer?.borderColor = NSColor(srgbRed: 0xC0 / 255.0, green: 0x84 / 255.0, blue: 0xFC / 255.0, alpha: 0.24).cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 10
        card.layer?.cornerCurve = .continuous
        return card
    }

    private func makeSectionHeading(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = primaryText
        return label
    }

    private func makeKeycapPill(_ text: String) -> NSView {
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = violetAccent.withAlphaComponent(0.20).cgColor
        pill.layer?.borderColor = violetAccent.withAlphaComponent(0.42).cgColor
        pill.layer?.borderWidth = 0.75
        pill.layer?.cornerRadius = 5
        pill.layer?.cornerCurve = .continuous

        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = primaryText
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 82)
        ])
        return pill
    }

    private var secondaryWidthConstraint: NSLayoutConstraint?
    private var primaryWidthConstraint: NSLayoutConstraint?

    private func setButtonTitle(_ title: String, on button: NSButton, isPrimary: Bool) {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let color = isPrimary ? NSColor.white : primaryText
        let attr = NSAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: color]
        )
        button.attributedTitle = attr
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let targetWidth = ceil(textWidth) + 26
        if isPrimary {
            primaryWidthConstraint?.isActive = false
            let constraint = button.widthAnchor.constraint(greaterThanOrEqualToConstant: max(86, targetWidth))
            constraint.isActive = true
            primaryWidthConstraint = constraint
        } else {
            secondaryWidthConstraint?.isActive = false
            let constraint = button.widthAnchor.constraint(greaterThanOrEqualToConstant: targetWidth)
            constraint.isActive = true
            secondaryWidthConstraint = constraint
        }
    }

    private func configureButton(_ button: NSButton, isPrimary: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.alignment = .center
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

        if isPrimary {
            button.layer?.backgroundColor = violetAccent.withAlphaComponent(0.92).cgColor
        } else {
            button.layer?.backgroundColor = violetAccent.withAlphaComponent(0.16).cgColor
            button.layer?.borderColor = violetAccent.withAlphaComponent(0.42).cgColor
            button.layer?.borderWidth = 1
        }
    }

    override func loadWindow() {
        // Window is created directly in init(mode:).
    }

    func windowWillClose(_ notification: Notification) {
        onDidClose?()
    }

    // MARK: - Actions

    @objc private func handleDismissClicked() {
        dismissGuide()
    }

    @objc private func handleSecondaryClicked() {
        switch currentMode {
        case .welcome:
            show(mode: .instructions, avoiding: lastAvoidingPanelFrame)
        case .instructions:
            onOpenSettings?()
        }
    }

    @objc private func handlePrimaryClicked() {
        dismissGuide()
    }

    private func dismissGuide() {
        close()
        onDismissToEditor?()
    }
}

private final class GuidePanel: NSPanel {
    var onEscapeOrClose: (() -> Void)?
    var onOpenSettingsShortcut: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if Int(event.keyCode) == kVK_Escape || (modifiers == [.command] && key == "w") {
            onEscapeOrClose?()
            return true
        }
        if modifiers == [.command] && key == "," {
            onOpenSettingsShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class VioletCardView: NSView {
    private let bgLayer = CAGradientLayer()
    private let auraLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor(srgbRed: 0xB8 / 255.0, green: 0x4D / 255.0, blue: 1.0, alpha: 0.88).cgColor

        bgLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        bgLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        bgLayer.colors = [
            NSColor(srgbRed: 0x21 / 255.0, green: 0x14 / 255.0, blue: 0x3E / 255.0, alpha: 0.98).cgColor,
            NSColor(srgbRed: 0x14 / 255.0, green: 0x0D / 255.0, blue: 0x28 / 255.0, alpha: 0.98).cgColor,
            NSColor(srgbRed: 0x0D / 255.0, green: 0x09 / 255.0, blue: 0x1A / 255.0, alpha: 0.99).cgColor
        ]
        bgLayer.locations = [0.0, 0.5, 1.0]
        layer?.addSublayer(bgLayer)

        auraLayer.type = .radial
        auraLayer.startPoint = CGPoint(x: 0.16, y: 0.88)
        auraLayer.endPoint = CGPoint(x: 0.85, y: 0.12)
        auraLayer.colors = [
            NSColor(srgbRed: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, alpha: 0.26).cgColor,
            NSColor(srgbRed: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, alpha: 0.0).cgColor
        ]
        layer?.addSublayer(auraLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        bgLayer.frame = bounds
        auraLayer.frame = bounds
    }
}

private final class GuideDragHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}
