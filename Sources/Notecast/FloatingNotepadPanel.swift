import AppKit
import Carbon.HIToolbox
import NotecastCore
import QuartzCore

private let panelCornerRadius: CGFloat = 14

/// Always-ready floating `NSPanel` supporting curated opaque/HUD backgrounds, active neon glow, Ghost Outline Mode, Notes List, and Command Palette.
@MainActor
final class FloatingNotepadPanel: NSPanel {
    let textView: MarkdownTextView
    let notesListView = NotesListView()
    let commandPaletteView = CommandPaletteView()

    var onTogglePin: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestHide: (() -> Void)?
    var onNewNote: (() -> Void)?
    var onToggleNotesList: (() -> Void)?
    var onToggleCommandPalette: (() -> Void)?
    var onToggleNotesSearch: (() -> Void)?
    var onShouldAllowGhostMode: (() -> Bool)?
    var onWakeFromGhost: (() -> Void)?

    private(set) var activePaletteMode: PaletteMode = .all
    private(set) var isGhosted = false

    private let rootContainer = NSView()
    private let hudEffectView = NSVisualEffectView()
    private let contentWrapperView = GhostContentWrapperView()
    private let headerView = HeaderDragView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Notecast")
    private let hotKeyHintLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let separator = SeparatorGlowView()
    private let neonOverlayView = NeonGlowOverlayView()
    private let ghostWakeZoneView = GhostWakeZoneView()

    private let notesListButton: NSButton
    private let searchButton: NSButton
    private let newNoteButton: NSButton
    private let pinButton: NSButton
    private let settingsButton: NSButton
    private let hideButton: NSButton

    private var surfaceStyle: SurfaceStyle
    private var panelOpacity: Double
    private var neonGlowEnabled: Bool
    private var neonAccent: NeonAccent
    private var isAlwaysOnTop: Bool
    private var ghostOnUnfocus: Bool
    private var isPanelActive = false

    init(
        contentRect: NSRect,
        fontSize: CGFloat,
        fontFamily: String,
        alwaysOnTop: Bool,
        followAllSpaces: Bool,
        surfaceStyle: SurfaceStyle,
        opacity: Double,
        neonGlowEnabled: Bool,
        neonAccent: NeonAccent,
        ghostOnUnfocus: Bool,
        hotKeyHint: String
    ) {
        self.surfaceStyle = surfaceStyle
        self.panelOpacity = opacity
        self.neonGlowEnabled = neonGlowEnabled
        self.neonAccent = neonAccent
        self.isAlwaysOnTop = alwaysOnTop
        self.ghostOnUnfocus = ghostOnUnfocus

        let scrollView = WrappingScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let initialWidth = max(240, contentRect.width)
        let textContainer = NSTextContainer(
            size: NSSize(width: initialWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let editor = MarkdownTextView(
            frame: .zero,
            textContainer: textContainer,
            fontSize: fontSize,
            fontFamily: fontFamily,
            accentColor: neonGlowEnabled ? neonAccent.nsColor : .controlAccentColor
        )
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        scrollView.documentView = editor
        self.textView = editor

        self.notesListButton = Self.makeHeaderButton(symbolName: "list.bullet", accessibilityLabel: "Notes List")
        self.searchButton = Self.makeHeaderButton(symbolName: "magnifyingglass", accessibilityLabel: "Search & Commands")
        self.newNoteButton = Self.makeHeaderButton(symbolName: "square.and.pencil", accessibilityLabel: "New Note")
        self.pinButton = Self.makeHeaderButton(symbolName: "pin.fill", accessibilityLabel: "Toggle Always on Top")
        self.settingsButton = Self.makeHeaderButton(symbolName: "gearshape", accessibilityLabel: "Settings")
        self.hideButton = Self.makeHeaderButton(symbolName: "xmark", accessibilityLabel: "Hide Notecast")

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        hotKeyHintLabel.stringValue = hotKeyHint

        configureWindowProperties(alwaysOnTop: alwaysOnTop, followAllSpaces: followAllSpaces)
        buildLayout(scrollView: scrollView)
        wireActions()
        applySurfaceStyle(surfaceStyle, opacity: opacity)
        applyNeonStyle(enabled: neonGlowEnabled, accent: neonAccent)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        isPanelActive = true
        setGhosted(false, animated: true)
    }

    override func resignKey() {
        super.resignKey()
        isPanelActive = false
        let allowGhost = onShouldAllowGhostMode?() ?? true
        setGhosted(ghostOnUnfocus && allowGhost, animated: true)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if Int(event.keyCode) == kVK_Escape {
            if isCommandPaletteVisible {
                hideCommandPalette()
                return true
            }
            if isNotesListVisible {
                hideNotesList()
                return true
            }
        }

        if modifiers == [.command] {
            switch key {
            case "p":
                onToggleCommandPalette?()
                return true
            case "n":
                onNewNote?()
                return true
            case "l":
                onToggleNotesList?()
                return true
            case ",":
                onOpenSettings?()
                return true
            default:
                break
            }
        } else if modifiers == [.command, .shift] {
            if key == "p" {
                onToggleNotesSearch?()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Appearance & Settings Application

    func applyAlwaysOnTop(_ enabled: Bool) {
        isAlwaysOnTop = enabled
        level = enabled ? .floating : .normal
        let symbolName = enabled ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Always on Top")
        pinButton.toolTip = enabled ? "Always on Top (On)" : "Always on Top (Off)"
        updatePinTint()
    }

    func applyFollowAllSpaces(_ enabled: Bool) {
        collectionBehavior = enabled ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    func applyGhostOnUnfocus(_ enabled: Bool) {
        ghostOnUnfocus = enabled
        if !enabled && isGhosted {
            setGhosted(false, animated: true)
        } else if enabled && !isPanelActive && isVisible {
            let allowGhost = onShouldAllowGhostMode?() ?? true
            setGhosted(allowGhost, animated: true)
        }
    }

    func applySurfaceStyle(_ style: SurfaceStyle, opacity: Double) {
        self.surfaceStyle = style
        self.panelOpacity = opacity

        if style.isOpaque {
            appearance = NSAppearance(named: style.isLight ? .aqua : .darkAqua)
        } else {
            appearance = nil
        }

        if !isGhosted {
            hudEffectView.isHidden = style.isOpaque
            rootContainer.layer?.backgroundColor = (style.backgroundColor ?? .clear).cgColor
            alphaValue = style.isOpaque ? 1.0 : CGFloat(opacity)
            invalidateShadow()
        }

        headerView.layer?.backgroundColor = (style.headerBackgroundColor ?? .clear).cgColor
        refreshActiveNeonVisuals(animated: false)

        if !notesListView.isHidden {
            notesListView.applySurfaceStyle(style)
        }
        if !commandPaletteView.isHidden {
            commandPaletteView.applyTheme(
                surfaceStyle: style,
                neonGlowEnabled: neonGlowEnabled,
                neonAccent: neonAccent
            )
        }
        textView.needsDisplay = true
    }

    func applyNeonStyle(enabled: Bool, accent: NeonAccent) {
        self.neonGlowEnabled = enabled
        self.neonAccent = accent

        textView.applyAccentColor(enabled ? accent.nsColor : .controlAccentColor)
        updatePinTint()
        refreshActiveNeonVisuals(animated: true)

        if !commandPaletteView.isHidden {
            commandPaletteView.applyTheme(
                surfaceStyle: surfaceStyle,
                neonGlowEnabled: enabled,
                neonAccent: accent
            )
        }
    }

    func applyFont(family: String, size: CGFloat) {
        textView.applyFont(family: family, size: size)
    }

    func updateNoteTitle(_ title: String) {
        titleLabel.stringValue = title.isEmpty ? "Notecast" : title
    }

    func updateHotKeyHint(_ hint: String) {
        hotKeyHintLabel.stringValue = hint
    }

    func updateSaveStatus(_ status: String) {
        statusLabel.stringValue = status
    }

    func setGhosted(_ ghosted: Bool, animated: Bool) {
        isGhosted = ghosted
        contentWrapperView.isGhosted = ghosted

        if ghosted {
            hudEffectView.isHidden = true
            rootContainer.layer?.backgroundColor = NSColor.clear.cgColor
            hasShadow = false
            alphaValue = 1.0
            ghostWakeZoneView.update(neonGlowEnabled: neonGlowEnabled, accentColor: neonAccent.nsColor, animated: false)
            ghostWakeZoneView.isHidden = false

            if animated {
                ghostWakeZoneView.alphaValue = 0.0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    contentWrapperView.animator().alphaValue = 0.0
                    ghostWakeZoneView.animator().alphaValue = 1.0
                }
            } else {
                contentWrapperView.alphaValue = 0.0
                ghostWakeZoneView.alphaValue = 1.0
            }
        } else {
            hudEffectView.isHidden = surfaceStyle.isOpaque
            rootContainer.layer?.backgroundColor = (surfaceStyle.backgroundColor ?? .clear).cgColor
            alphaValue = surfaceStyle.isOpaque ? 1.0 : CGFloat(panelOpacity)
            hasShadow = true
            invalidateShadow()
            ghostWakeZoneView.isHidden = true
            ghostWakeZoneView.resetHover()

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    contentWrapperView.animator().alphaValue = 1.0
                }
            } else {
                contentWrapperView.alphaValue = 1.0
            }
        }

        refreshActiveNeonVisuals(animated: animated)
    }

    // MARK: - Overlays (`NotesListView` & `CommandPaletteView`)

    var isNotesListVisible: Bool {
        !notesListView.isHidden
    }

    var isCommandPaletteVisible: Bool {
        !commandPaletteView.isHidden
    }

    func showNotesList(notes: [NoteMetadata], activeNoteID: UUID?) {
        commandPaletteView.isHidden = true
        notesListView.update(
            notes: notes,
            activeNoteID: activeNoteID,
            surfaceStyle: surfaceStyle,
            neonAccent: neonAccent
        )
        notesListView.isHidden = false
        notesListView.focusList()
    }

    func hideNotesList() {
        notesListView.isHidden = true
        if commandPaletteView.isHidden {
            makeFirstResponder(textView)
        }
    }

    func showCommandPalette(mode: PaletteMode) {
        activePaletteMode = mode
        commandPaletteView.isHidden = false
        commandPaletteView.openPalette(
            mode: mode,
            surfaceStyle: surfaceStyle,
            neonGlowEnabled: neonGlowEnabled,
            neonAccent: neonAccent
        )
    }

    func hideCommandPalette() {
        commandPaletteView.isHidden = true
        if isNotesListVisible {
            notesListView.focusList()
        } else {
            makeFirstResponder(textView)
        }
    }

    func dismissOverlaysAndFocusEditor() {
        commandPaletteView.isHidden = true
        notesListView.isHidden = true
        makeFirstResponder(textView)
    }

    // MARK: - Setup

    private func configureWindowProperties(alwaysOnTop: Bool, followAllSpaces: Bool) {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = WindowFrameClamper.minSize

        applyAlwaysOnTop(alwaysOnTop)
        applyFollowAllSpaces(followAllSpaces)
    }

    private func buildLayout(scrollView: NSScrollView) {
        rootContainer.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.wantsLayer = true
        rootContainer.layer?.cornerRadius = panelCornerRadius
        rootContainer.layer?.cornerCurve = .continuous
        rootContainer.layer?.masksToBounds = true
        contentView = rootContainer

        hudEffectView.translatesAutoresizingMaskIntoConstraints = false
        hudEffectView.material = .hudWindow
        hudEffectView.blendingMode = .behindWindow
        hudEffectView.state = .active

        contentWrapperView.translatesAutoresizingMaskIntoConstraints = false
        contentWrapperView.wantsLayer = true

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NotecastBrandIcon.headerIconImage(
            accentColor: neonGlowEnabled ? neonAccent.nsColor : nil,
            isActive: isPanelActive
        )

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        hotKeyHintLabel.translatesAutoresizingMaskIntoConstraints = false
        hotKeyHintLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        hotKeyHintLabel.textColor = .tertiaryLabelColor
        hotKeyHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        separator.translatesAutoresizingMaskIntoConstraints = false

        notesListButton.toolTip = "Notes List (⌘L)"
        searchButton.toolTip = "Search & Commands (⌘P) · Notes Only (⌘⇧P)"
        newNoteButton.toolTip = "New Note (⌘N)"
        settingsButton.toolTip = "Settings (⌘,)"
        hideButton.toolTip = "Hide"

        let rightStack = NSStackView(views: [
            statusLabel,
            notesListButton,
            searchButton,
            newNoteButton,
            pinButton,
            settingsButton,
            hideButton
        ])
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.orientation = .horizontal
        rightStack.spacing = 2
        rightStack.alignment = .centerY
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        headerView.addSubview(iconView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(hotKeyHintLabel)
        headerView.addSubview(rightStack)

        notesListView.translatesAutoresizingMaskIntoConstraints = false
        notesListView.isHidden = true

        commandPaletteView.translatesAutoresizingMaskIntoConstraints = false
        commandPaletteView.isHidden = true

        contentWrapperView.addSubview(headerView)
        contentWrapperView.addSubview(separator)
        contentWrapperView.addSubview(scrollView)
        contentWrapperView.addSubview(notesListView)
        contentWrapperView.addSubview(commandPaletteView)

        neonOverlayView.translatesAutoresizingMaskIntoConstraints = false

        ghostWakeZoneView.translatesAutoresizingMaskIntoConstraints = false
        ghostWakeZoneView.isHidden = true
        ghostWakeZoneView.toolTip = "Click to wake Notecast"

        rootContainer.addSubview(hudEffectView)
        rootContainer.addSubview(contentWrapperView)
        rootContainer.addSubview(ghostWakeZoneView)
        rootContainer.addSubview(neonOverlayView)

        NSLayoutConstraint.activate([
            hudEffectView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            hudEffectView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            hudEffectView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            hudEffectView.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),

            contentWrapperView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            contentWrapperView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            contentWrapperView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            contentWrapperView.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),

            headerView.topAnchor.constraint(equalTo: contentWrapperView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 36),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            hotKeyHintLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            hotKeyHintLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            hotKeyHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -6),

            rightStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            rightStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            notesListButton.widthAnchor.constraint(equalToConstant: 22),
            notesListButton.heightAnchor.constraint(equalToConstant: 22),
            searchButton.widthAnchor.constraint(equalToConstant: 22),
            searchButton.heightAnchor.constraint(equalToConstant: 22),
            newNoteButton.widthAnchor.constraint(equalToConstant: 22),
            newNoteButton.heightAnchor.constraint(equalToConstant: 22),
            pinButton.widthAnchor.constraint(equalToConstant: 22),
            pinButton.heightAnchor.constraint(equalToConstant: 22),
            settingsButton.widthAnchor.constraint(equalToConstant: 22),
            settingsButton.heightAnchor.constraint(equalToConstant: 22),
            hideButton.widthAnchor.constraint(equalToConstant: 22),
            hideButton.heightAnchor.constraint(equalToConstant: 22),

            separator.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.5),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor),

            notesListView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            notesListView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
            notesListView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
            notesListView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor),

            commandPaletteView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            commandPaletteView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
            commandPaletteView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
            commandPaletteView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor),

            neonOverlayView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            neonOverlayView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            neonOverlayView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            neonOverlayView.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),

            ghostWakeZoneView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            ghostWakeZoneView.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
            ghostWakeZoneView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            ghostWakeZoneView.widthAnchor.constraint(equalTo: rootContainer.widthAnchor, multiplier: 0.55)
        ])
    }

    private func wireActions() {
        notesListButton.target = self
        notesListButton.action = #selector(handleNotesListTapped)

        searchButton.target = self
        searchButton.action = #selector(handleSearchTapped)

        newNoteButton.target = self
        newNoteButton.action = #selector(handleNewNoteTapped)

        pinButton.target = self
        pinButton.action = #selector(handlePinTapped)

        settingsButton.target = self
        settingsButton.action = #selector(handleSettingsTapped)

        hideButton.target = self
        hideButton.action = #selector(handleHideTapped)

        ghostWakeZoneView.onWake = { [weak self] in
            self?.onWakeFromGhost?()
        }
    }

    private func updatePinTint() {
        if isAlwaysOnTop {
            pinButton.contentTintColor = neonGlowEnabled ? neonAccent.nsColor : .controlAccentColor
        } else {
            pinButton.contentTintColor = .secondaryLabelColor
        }
    }

    private func refreshActiveNeonVisuals(animated: Bool) {
        let glowActive = isPanelActive && neonGlowEnabled
        let accentColor = neonAccent.nsColor

        iconView.image = NotecastBrandIcon.headerIconImage(
            accentColor: glowActive ? accentColor : nil,
            isActive: isPanelActive
        )
        separator.update(
            glowActive: glowActive,
            accentColor: accentColor,
            surfaceStyle: surfaceStyle
        )
        neonOverlayView.update(
            isActive: isPanelActive,
            isGhosted: isGhosted,
            neonGlowEnabled: neonGlowEnabled,
            accentColor: accentColor,
            surfaceStyle: surfaceStyle,
            animated: animated
        )
        ghostWakeZoneView.update(neonGlowEnabled: neonGlowEnabled, accentColor: accentColor, animated: animated)
    }

    // MARK: - Button Selectors

    @objc private func handleNotesListTapped() {
        onToggleNotesList?()
    }

    @objc private func handleSearchTapped() {
        onToggleCommandPalette?()
    }

    @objc private func handleNewNoteTapped() {
        onNewNote?()
    }

    @objc private func handlePinTapped() {
        onTogglePin?()
    }

    @objc private func handleSettingsTapped() {
        onOpenSettings?()
    }

    @objc private func handleHideTapped() {
        onRequestHide?()
    }

    private static func makeHeaderButton(symbolName: String, accessibilityLabel: String) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.imageScaling = .scaleProportionallyDown
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        return button
    }
}

/// Wrapper container that forwards hits normally when awake and passes interior clicks through when ghosted.
private final class GhostContentWrapperView: NSView {
    var isGhosted = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isGhosted ? nil : super.hitTest(point)
    }
}

/// Feathered right-side dual-tone click-to-wake zone in Ghost Outline Mode; fades smoothly from 0 alpha so the left side remains click-through.
private final class GhostWakeZoneView: NSView {
    var onWake: (() -> Void)?

    private let contrastGradientLayer = CAGradientLayer()
    private let accentGradientLayer = CAGradientLayer()
    private let gripPill = NSView()
    private var trackingArea: NSTrackingArea?

    private var neonGlowEnabled = true
    private var accentColor = NeonAccent.cyan.nsColor
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        contrastGradientLayer.frame = bounds
        accentGradientLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        onWake?()
    }

    func resetHover() {
        guard isHovered else { return }
        isHovered = false
        applyAppearance(animated: false)
    }

    func update(neonGlowEnabled: Bool, accentColor: NSColor, animated: Bool) {
        self.neonGlowEnabled = neonGlowEnabled
        self.accentColor = accentColor
        applyAppearance(animated: animated)
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        let stops: [NSNumber] = [0.0, 0.16, 0.36, 0.58, 0.80, 1.0]

        contrastGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        contrastGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        contrastGradientLayer.locations = stops
        layer?.addSublayer(contrastGradientLayer)

        accentGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        accentGradientLayer.locations = stops
        layer?.addSublayer(accentGradientLayer)

        gripPill.translatesAutoresizingMaskIntoConstraints = false
        gripPill.wantsLayer = true
        gripPill.layer?.cornerRadius = 2
        gripPill.layer?.borderWidth = 0.75
        gripPill.layer?.borderColor = NSColor.black.withAlphaComponent(0.45).cgColor
        gripPill.layer?.shadowOffset = .zero
        gripPill.layer?.shadowRadius = 4
        addSubview(gripPill)

        NSLayoutConstraint.activate([
            gripPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            gripPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            gripPill.widthAnchor.constraint(equalToConstant: 4),
            gripPill.heightAnchor.constraint(equalToConstant: 34)
        ])

        applyAppearance(animated: false)
    }

    private func applyAppearance(animated: Bool) {
        let slateBase = NSColor(srgbRed: 0x14 / 255.0, green: 0x19 / 255.0, blue: 0x24 / 255.0, alpha: 1.0)
        let contrastAlphas: [CGFloat] = isHovered
            ? [0.0, 0.018, 0.055, 0.11, 0.17, 0.22]
            : [0.0, 0.01, 0.035, 0.075, 0.12, 0.16]
        let accentBase = neonGlowEnabled ? accentColor : NSColor.white
        let accentAlphas: [CGFloat] = isHovered
            ? [0.0, 0.015, 0.045, 0.095, 0.16, 0.22]
            : [0.0, 0.008, 0.025, 0.06, 0.10, 0.15]

        let apply = {
            self.contrastGradientLayer.colors = contrastAlphas.map { slateBase.withAlphaComponent($0).cgColor }
            self.accentGradientLayer.colors = accentAlphas.map { accentBase.withAlphaComponent($0).cgColor }

            if self.neonGlowEnabled {
                self.gripPill.layer?.backgroundColor = self.accentColor.withAlphaComponent(self.isHovered ? 0.96 : 0.76).cgColor
                self.gripPill.layer?.shadowColor = self.accentColor.cgColor
                self.gripPill.layer?.shadowOpacity = self.isHovered ? 0.6 : 0.38
            } else {
                self.gripPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(self.isHovered ? 0.90 : 0.70).cgColor
                self.gripPill.layer?.shadowColor = NSColor.black.cgColor
                self.gripPill.layer?.shadowOpacity = 0.28
            }
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            apply()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        }
    }
}

/// Scroll view that keeps its hosted `NSTextView` and `NSTextContainer` width synced to clip bounds for reliable word wrap.
private final class WrappingScrollView: NSScrollView {
    override func layout() {
        super.layout()
        syncTextViewWidth()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncTextViewWidth()
    }

    private func syncTextViewWidth() {
        guard let textView = documentView as? NSTextView else { return }
        let clipBounds = contentView.bounds
        let clipWidth = max(100, clipBounds.width)

        if abs(textView.frame.width - clipWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: clipWidth, height: max(textView.frame.height, clipBounds.height)))
        }

        let insetX = textView.textContainerInset.width * 2
        let targetContainerWidth = max(40, clipWidth - insetX)
        if let textContainer = textView.textContainer,
           abs(textContainer.containerSize.width - targetContainerWidth) > 0.5
        {
            textContainer.containerSize = NSSize(width: targetContainerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
    }
}

/// Header divider rendering a luminous neon hairline gradient when active.
private final class SeparatorGlowView: NSView {
    private let glowLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        glowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(glowLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        glowLayer.frame = bounds
    }

    func update(glowActive: Bool, accentColor: NSColor, surfaceStyle: SurfaceStyle) {
        glowLayer.frame = bounds
        if glowActive {
            glowLayer.isHidden = false
            glowLayer.colors = [
                accentColor.withAlphaComponent(0.12).cgColor,
                accentColor.withAlphaComponent(0.9).cgColor,
                accentColor.withAlphaComponent(0.12).cgColor
            ]
            layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            glowLayer.isHidden = true
            layer?.backgroundColor = surfaceStyle.calmSeparatorColor.cgColor
        }
    }
}

/// Non-interactive overlay drawing active neon glow, calm borders, or dual-contrast Ghost Outline reticle arcs.
private final class NeonGlowOverlayView: NSView {
    private let innerGlowLayer = CAShapeLayer()
    private let ghostContrastOutlineLayer = CAShapeLayer()
    private let ghostOutlineLayer = CAShapeLayer()
    private let ghostContrastCornersLayer = CAShapeLayer()
    private let ghostCornersLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = panelCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        innerGlowLayer.fillRule = .evenOdd
        innerGlowLayer.shadowOffset = .zero
        innerGlowLayer.shadowRadius = 12
        layer?.addSublayer(innerGlowLayer)

        ghostContrastOutlineLayer.fillColor = nil
        ghostContrastOutlineLayer.lineWidth = 2.5
        ghostContrastOutlineLayer.lineDashPattern = [5, 4]
        ghostContrastOutlineLayer.strokeColor = NSColor.black.withAlphaComponent(0.38).cgColor
        ghostContrastOutlineLayer.opacity = 0
        layer?.addSublayer(ghostContrastOutlineLayer)

        ghostOutlineLayer.fillColor = nil
        ghostOutlineLayer.lineWidth = 1.25
        ghostOutlineLayer.lineDashPattern = [5, 4]
        ghostOutlineLayer.opacity = 0
        layer?.addSublayer(ghostOutlineLayer)

        ghostContrastCornersLayer.fillColor = nil
        ghostContrastCornersLayer.lineWidth = 3.75
        ghostContrastCornersLayer.lineCap = .round
        ghostContrastCornersLayer.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
        ghostContrastCornersLayer.opacity = 0
        layer?.addSublayer(ghostContrastCornersLayer)

        ghostCornersLayer.fillColor = nil
        ghostCornersLayer.lineWidth = 2.0
        ghostCornersLayer.lineCap = .round
        ghostCornersLayer.shadowOffset = .zero
        ghostCornersLayer.shadowRadius = 4
        ghostCornersLayer.opacity = 0
        layer?.addSublayer(ghostCornersLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    func update(
        isActive: Bool,
        isGhosted: Bool,
        neonGlowEnabled: Bool,
        accentColor: NSColor,
        surfaceStyle: SurfaceStyle,
        animated: Bool
    ) {
        updatePaths()

        let applyChanges = {
            if isGhosted {
                self.layer?.borderWidth = 0
                self.innerGlowLayer.shadowOpacity = 0.0

                self.ghostContrastOutlineLayer.opacity = 1.0

                self.ghostOutlineLayer.strokeColor = neonGlowEnabled
                    ? accentColor.withAlphaComponent(0.78).cgColor
                    : NSColor.white.withAlphaComponent(0.80).cgColor
                self.ghostOutlineLayer.opacity = 1.0

                self.ghostContrastCornersLayer.opacity = 1.0

                self.ghostCornersLayer.strokeColor = neonGlowEnabled
                    ? accentColor.withAlphaComponent(0.95).cgColor
                    : NSColor.white.withAlphaComponent(0.90).cgColor
                self.ghostCornersLayer.shadowColor = neonGlowEnabled
                    ? accentColor.cgColor
                    : NSColor.black.cgColor
                self.ghostCornersLayer.shadowOpacity = neonGlowEnabled ? 0.55 : 0.25
                self.ghostCornersLayer.opacity = 1.0
            } else {
                self.ghostContrastOutlineLayer.opacity = 0.0
                self.ghostOutlineLayer.opacity = 0.0
                self.ghostContrastCornersLayer.opacity = 0.0
                self.ghostCornersLayer.opacity = 0.0

                if isActive && neonGlowEnabled {
                    self.layer?.borderWidth = 1.5
                    self.layer?.borderColor = accentColor.withAlphaComponent(0.95).cgColor
                    self.innerGlowLayer.fillColor = accentColor.cgColor
                    self.innerGlowLayer.shadowColor = accentColor.cgColor
                    self.innerGlowLayer.shadowOpacity = 0.55
                } else {
                    self.layer?.borderWidth = 0.75
                    self.layer?.borderColor = surfaceStyle.calmBorderColor.cgColor
                    self.innerGlowLayer.shadowOpacity = 0.0
                }
            }
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            applyChanges()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyChanges()
            CATransaction.commit()
        }
    }

    private func updatePaths() {
        guard !bounds.isEmpty else { return }
        innerGlowLayer.frame = bounds
        ghostContrastOutlineLayer.frame = bounds
        ghostOutlineLayer.frame = bounds
        ghostContrastCornersLayer.frame = bounds
        ghostCornersLayer.frame = bounds

        let outerRect = bounds.insetBy(dx: -24, dy: -24)
        let innerGlowPath = CGMutablePath()
        innerGlowPath.addRect(outerRect)
        innerGlowPath.addPath(CGPath(roundedRect: bounds, cornerWidth: panelCornerRadius, cornerHeight: panelCornerRadius, transform: nil))
        innerGlowLayer.path = innerGlowPath

        let outlineRect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let outlineRadius = max(2, panelCornerRadius - 0.75)
        let outlineCGPath = CGPath(roundedRect: outlineRect, cornerWidth: outlineRadius, cornerHeight: outlineRadius, transform: nil)
        ghostContrastOutlineLayer.path = outlineCGPath
        ghostOutlineLayer.path = outlineCGPath

        let r = bounds.insetBy(dx: 1.0, dy: 1.0)
        let cr = max(2, panelCornerRadius - 1.0)
        let arm: CGFloat = 12
        let cornersPath = CGMutablePath()

        // Bottom-left
        cornersPath.move(to: CGPoint(x: r.minX, y: r.minY + cr + arm))
        cornersPath.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        cornersPath.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + cr, y: r.minY), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.minX + cr + arm, y: r.minY))

        // Bottom-right
        cornersPath.move(to: CGPoint(x: r.maxX - cr - arm, y: r.minY))
        cornersPath.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        cornersPath.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + cr), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.maxX, y: r.minY + cr + arm))

        // Top-right
        cornersPath.move(to: CGPoint(x: r.maxX, y: r.maxY - cr - arm))
        cornersPath.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cr))
        cornersPath.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - cr, y: r.maxY), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.maxX - cr - arm, y: r.maxY))

        // Top-left
        cornersPath.move(to: CGPoint(x: r.minX + cr + arm, y: r.maxY))
        cornersPath.addLine(to: CGPoint(x: r.minX + cr, y: r.maxY))
        cornersPath.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - cr), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.minX, y: r.maxY - cr - arm))

        ghostContrastCornersLayer.path = cornersPath
        ghostCornersLayer.path = cornersPath
    }
}

/// Draggable header bar that lets the user reposition the borderless floating panel.
private final class HeaderDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
