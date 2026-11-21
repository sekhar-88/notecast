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
    private let ghostPillHandle = GhostWakePillView()

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
            ghostPillHandle.update(neonGlowEnabled: neonGlowEnabled, accentColor: neonAccent.nsColor)
            ghostPillHandle.isHidden = false

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    contentWrapperView.animator().alphaValue = 0.0
                    ghostPillHandle.animator().alphaValue = 0.85
                }
            } else {
                contentWrapperView.alphaValue = 0.0
                ghostPillHandle.alphaValue = 0.85
            }
        } else {
            hudEffectView.isHidden = surfaceStyle.isOpaque
            rootContainer.layer?.backgroundColor = (surfaceStyle.backgroundColor ?? .clear).cgColor
            alphaValue = surfaceStyle.isOpaque ? 1.0 : CGFloat(panelOpacity)
            hasShadow = true
            invalidateShadow()
            ghostPillHandle.isHidden = true

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
        iconView.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor

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

        ghostPillHandle.translatesAutoresizingMaskIntoConstraints = false
        ghostPillHandle.isHidden = true
        ghostPillHandle.toolTip = "Click to wake Notecast"

        rootContainer.addSubview(hudEffectView)
        rootContainer.addSubview(contentWrapperView)
        rootContainer.addSubview(neonOverlayView)
        rootContainer.addSubview(ghostPillHandle)

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

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

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

            ghostPillHandle.topAnchor.constraint(equalTo: rootContainer.topAnchor, constant: 6),
            ghostPillHandle.centerXAnchor.constraint(equalTo: rootContainer.centerXAnchor),
            ghostPillHandle.widthAnchor.constraint(equalToConstant: 38),
            ghostPillHandle.heightAnchor.constraint(equalToConstant: 5)
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

        ghostPillHandle.onWake = { [weak self] in
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

        iconView.contentTintColor = glowActive ? accentColor : .secondaryLabelColor
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
        ghostPillHandle.update(neonGlowEnabled: neonGlowEnabled, accentColor: accentColor)
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

/// Minimalist top-edge capsule handle visible in Ghost Outline Mode so the user can wake the notepad with a click.
private final class GhostWakePillView: NSView {
    var onWake: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 2.5
        layer?.masksToBounds = false
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(neonGlowEnabled: Bool, accentColor: NSColor) {
        if neonGlowEnabled {
            layer?.backgroundColor = accentColor.withAlphaComponent(0.75).cgColor
            layer?.shadowColor = accentColor.cgColor
            layer?.shadowOpacity = 0.45
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.25
        }
    }

    override func mouseDown(with event: NSEvent) {
        onWake?()
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

/// Non-interactive overlay drawing active neon glow, calm borders, or Ghost Outline reticle arcs.
private final class NeonGlowOverlayView: NSView {
    private let innerGlowLayer = CAShapeLayer()
    private let ghostOutlineLayer = CAShapeLayer()
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

        ghostOutlineLayer.fillColor = nil
        ghostOutlineLayer.lineWidth = 1.0
        ghostOutlineLayer.lineDashPattern = [5, 4]
        ghostOutlineLayer.opacity = 0
        layer?.addSublayer(ghostOutlineLayer)

        ghostCornersLayer.fillColor = nil
        ghostCornersLayer.lineWidth = 1.75
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

                self.ghostOutlineLayer.strokeColor = neonGlowEnabled
                    ? accentColor.withAlphaComponent(0.42).cgColor
                    : surfaceStyle.calmBorderColor.withAlphaComponent(0.7).cgColor
                self.ghostOutlineLayer.opacity = 1.0

                self.ghostCornersLayer.strokeColor = neonGlowEnabled
                    ? accentColor.withAlphaComponent(0.85).cgColor
                    : NSColor.white.withAlphaComponent(0.65).cgColor
                self.ghostCornersLayer.shadowColor = neonGlowEnabled
                    ? accentColor.cgColor
                    : NSColor.black.cgColor
                self.ghostCornersLayer.shadowOpacity = neonGlowEnabled ? 0.5 : 0.25
                self.ghostCornersLayer.opacity = 1.0
            } else {
                self.ghostOutlineLayer.opacity = 0.0
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
        ghostOutlineLayer.frame = bounds
        ghostCornersLayer.frame = bounds

        let outerRect = bounds.insetBy(dx: -24, dy: -24)
        let innerGlowPath = CGMutablePath()
        innerGlowPath.addRect(outerRect)
        innerGlowPath.addPath(CGPath(roundedRect: bounds, cornerWidth: panelCornerRadius, cornerHeight: panelCornerRadius, transform: nil))
        innerGlowLayer.path = innerGlowPath

        let outlineRect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let outlineRadius = max(2, panelCornerRadius - 0.75)
        ghostOutlineLayer.path = CGPath(roundedRect: outlineRect, cornerWidth: outlineRadius, cornerHeight: outlineRadius, transform: nil)

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
