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
    var onOpenGuide: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestHide: (() -> Void)?
    var onNewNote: (() -> Void)?
    var onToggleNotesList: (() -> Void)?
    var onToggleCommandPalette: (() -> Void)?
    var onToggleNotesSearch: (() -> Void)?
    var onShouldAllowGhostMode: (() -> Bool)?
    var onWakeFromGhost: (() -> Void)?
    var onGhostDragEnded: (() -> Void)?
    var onHeaderDragEnded: (() -> Void)?
    var onCommandPaletteHidden: (() -> Void)?
    var onShouldEnsureWakeZoneOnScreen: (() -> Void)?

    private struct HeaderIconCacheKey: Hashable {
        let accent: NeonAccent?
        let isActive: Bool
    }

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

    private let notesListButton: HeaderIconButton
    private let searchButton: HeaderIconButton
    private let newNoteButton: HeaderIconButton
    private let pinButton: HeaderIconButton
    private let helpButton: HeaderIconButton
    private let settingsButton: HeaderIconButton
    private let hideButton: HeaderIconButton

    private var surfaceStyle: SurfaceStyle
    private var panelOpacity: Double
    private var neonGlowEnabled: Bool
    private var neonAccent: NeonAccent
    private var isAlwaysOnTop: Bool
    private var ghostOnUnfocus: Bool
    private var ghostWakeZoneFraction: Double
    private var ghostWakeZoneWidthConstraint: NSLayoutConstraint?
    private var isPanelActive = false
    private var headerIconCache: [HeaderIconCacheKey: NSImage] = [:]

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
        ghostWakeZoneFraction: Double,
        hotKeyHint: String
    ) {
        self.surfaceStyle = surfaceStyle
        self.panelOpacity = opacity
        self.neonGlowEnabled = neonGlowEnabled
        self.neonAccent = neonAccent
        self.isAlwaysOnTop = alwaysOnTop
        self.ghostOnUnfocus = ghostOnUnfocus
        self.ghostWakeZoneFraction = AppSettings.clampGhostWakeZoneFraction(ghostWakeZoneFraction)

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
        self.helpButton = Self.makeHeaderButton(
            symbolName: "questionmark.circle.fill",
            accessibilityLabel: "Instructions & Shortcuts",
            pointSize: 12.5,
            weight: .semibold
        )
        self.helpButton.restTintColor = NSColor(srgbRed: 0.72, green: 0.36, blue: 1.0, alpha: 0.92)
        self.helpButton.hoverTintOverride = NSColor(srgbRed: 0.78, green: 0.44, blue: 1.0, alpha: 1.0)
        self.helpButton.activeAccentColor = NeonAccent.violet.nsColor
        self.settingsButton = Self.makeHeaderButton(symbolName: "gearshape", accessibilityLabel: "Settings")
        self.hideButton = Self.makeHeaderButton(symbolName: "xmark", accessibilityLabel: "Hide Notecast")
        self.hideButton.hoverTintOverride = NSColor(srgbRed: 1.0, green: 0.38, blue: 0.42, alpha: 0.95)

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

    override var canBecomeKey: Bool { !isGhosted }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        guard !isGhosted else { return }
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
            case "?":
                onOpenGuide?()
                return true
            default:
                break
            }
        } else if modifiers == [.command, .shift] {
            if key == "p" {
                onToggleNotesSearch?()
                return true
            }
            if key == "/" || key == "?" {
                onOpenGuide?()
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

    func applyGhostWakeZoneFraction(_ fraction: Double, previewOverlay: Bool = false) {
        let clamped = AppSettings.clampGhostWakeZoneFraction(fraction)
        ghostWakeZoneFraction = clamped

        if let existing = ghostWakeZoneWidthConstraint {
            existing.isActive = false
        }
        let updated = ghostWakeZoneView.widthAnchor.constraint(
            equalTo: rootContainer.widthAnchor,
            multiplier: CGFloat(clamped)
        )
        updated.isActive = true
        ghostWakeZoneWidthConstraint = updated
        rootContainer.layoutSubtreeIfNeeded()

        if !isGhosted {
            if previewOverlay {
                ghostWakeZoneView.update(neonGlowEnabled: neonGlowEnabled, accentColor: neonAccent.nsColor, animated: false)
                ghostWakeZoneView.alphaValue = 1.0
                ghostWakeZoneView.isHidden = false
            } else {
                ghostWakeZoneView.isHidden = true
            }
        }
    }

    func applySurfaceStyle(_ style: SurfaceStyle, opacity: Double) {
        let styleChanged = (self.surfaceStyle != style)
        self.surfaceStyle = style
        self.panelOpacity = opacity

        let targetAppearanceName: NSAppearance.Name? = style.isOpaque
            ? (style.isLight ? .aqua : .darkAqua)
            : nil
        if appearance?.name != targetAppearanceName {
            appearance = targetAppearanceName.flatMap(NSAppearance.init(named:))
        }

        if !isGhosted {
            let hudVisibilityChanged = (hudEffectView.isHidden != style.isOpaque)
            hudEffectView.isHidden = style.isOpaque
            rootContainer.layer?.backgroundColor = (style.backgroundColor ?? .clear).cgColor
            alphaValue = style.isOpaque ? 1.0 : CGFloat(opacity)
            if styleChanged || hudVisibilityChanged {
                invalidateShadow()
            }
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
        let next = title.isEmpty ? "Notecast" : title
        if titleLabel.stringValue != next {
            titleLabel.stringValue = next
        }
    }

    func updateHotKeyHint(_ hint: String) {
        if hotKeyHintLabel.stringValue != hint {
            hotKeyHintLabel.stringValue = hint
        }
    }

    func updateSaveStatus(_ status: String) {
        if statusLabel.stringValue != status {
            statusLabel.stringValue = status
        }
    }

    func setGhosted(_ ghosted: Bool, animated: Bool) {
        guard isGhosted != ghosted else {
            refreshActiveNeonVisuals(animated: animated)
            return
        }

        isGhosted = ghosted
        becomesKeyOnlyIfNeeded = ghosted
        contentWrapperView.isGhosted = ghosted

        if ghosted {
            for button in headerButtons {
                button.resetHover()
            }
            onShouldEnsureWakeZoneOnScreen?()
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
        syncHeaderOverlayStates()
        notesListView.focusList()
    }

    func hideNotesList() {
        notesListView.isHidden = true
        syncHeaderOverlayStates()
        if commandPaletteView.isHidden {
            makeFirstResponder(textView)
        }
    }

    func showCommandPalette(mode: PaletteMode) {
        activePaletteMode = mode
        commandPaletteView.isHidden = false
        syncHeaderOverlayStates()
        commandPaletteView.openPalette(
            mode: mode,
            surfaceStyle: surfaceStyle,
            neonGlowEnabled: neonGlowEnabled,
            neonAccent: neonAccent
        )
    }

    func hideCommandPalette() {
        let wasVisible = !commandPaletteView.isHidden
        commandPaletteView.isHidden = true
        if wasVisible {
            onCommandPaletteHidden?()
        }
        syncHeaderOverlayStates()
        if isNotesListVisible {
            notesListView.focusList()
        } else {
            makeFirstResponder(textView)
        }
    }

    func dismissOverlaysAndFocusEditor() {
        let paletteWasVisible = !commandPaletteView.isHidden
        commandPaletteView.isHidden = true
        notesListView.isHidden = true
        if paletteWasVisible {
            onCommandPaletteHidden?()
        }
        syncHeaderOverlayStates()
        makeFirstResponder(textView)
    }

    func setGuideActive(_ active: Bool) {
        helpButton.isActiveState = active
    }

    func setSettingsActive(_ active: Bool) {
        settingsButton.isActiveState = active
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
        helpButton.toolTip = "Instructions & Shortcuts (⌘?)"
        settingsButton.toolTip = "Settings (⌘, · Global ⌥⌘,)"
        hideButton.toolTip = "Hide"

        let rightStack = NSStackView(views: [
            statusLabel,
            notesListButton,
            searchButton,
            newNoteButton,
            pinButton,
            helpButton,
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
        ghostWakeZoneView.toolTip = "Click to wake · Drag to move"

        rootContainer.addSubview(hudEffectView)
        rootContainer.addSubview(contentWrapperView)
        rootContainer.addSubview(ghostWakeZoneView)
        rootContainer.addSubview(neonOverlayView)

        let wakeWidthConstraint = ghostWakeZoneView.widthAnchor.constraint(
            equalTo: rootContainer.widthAnchor,
            multiplier: CGFloat(ghostWakeZoneFraction)
        )
        ghostWakeZoneWidthConstraint = wakeWidthConstraint

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

            notesListButton.widthAnchor.constraint(equalToConstant: 24),
            notesListButton.heightAnchor.constraint(equalToConstant: 24),
            searchButton.widthAnchor.constraint(equalToConstant: 24),
            searchButton.heightAnchor.constraint(equalToConstant: 24),
            newNoteButton.widthAnchor.constraint(equalToConstant: 24),
            newNoteButton.heightAnchor.constraint(equalToConstant: 24),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),
            helpButton.widthAnchor.constraint(equalToConstant: 24),
            helpButton.heightAnchor.constraint(equalToConstant: 24),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),
            hideButton.widthAnchor.constraint(equalToConstant: 24),
            hideButton.heightAnchor.constraint(equalToConstant: 24),

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
            wakeWidthConstraint
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

        helpButton.target = self
        helpButton.action = #selector(handleHelpTapped)

        settingsButton.target = self
        settingsButton.action = #selector(handleSettingsTapped)

        hideButton.target = self
        hideButton.action = #selector(handleHideTapped)

        ghostWakeZoneView.onWake = { [weak self] in
            self?.onWakeFromGhost?()
        }
        ghostWakeZoneView.onDragEnded = { [weak self] in
            self?.onGhostDragEnded?()
        }
        headerView.onDragEnded = { [weak self] in
            self?.onHeaderDragEnded?()
        }
    }

    private var headerButtons: [HeaderIconButton] {
        [notesListButton, searchButton, newNoteButton, pinButton, helpButton, settingsButton, hideButton]
    }

    private func syncHeaderOverlayStates() {
        notesListButton.isActiveState = isNotesListVisible
        searchButton.isActiveState = isCommandPaletteVisible
    }

    private func refreshHeaderButtonsTheme() {
        let accent: NSColor = neonGlowEnabled ? neonAccent.nsColor : .controlAccentColor
        for button in headerButtons {
            if button !== helpButton {
                button.activeAccentColor = accent
            }
        }
        pinButton.isActiveState = isAlwaysOnTop
        syncHeaderOverlayStates()
    }

    private func updatePinTint() {
        refreshHeaderButtonsTheme()
    }

    private func refreshActiveNeonVisuals(animated: Bool) {
        let glowActive = isPanelActive && neonGlowEnabled
        let accentColor = neonAccent.nsColor

        refreshHeaderButtonsTheme()

        let iconKey = HeaderIconCacheKey(
            accent: glowActive ? neonAccent : nil,
            isActive: isPanelActive
        )
        let headerImage: NSImage
        if let cached = headerIconCache[iconKey] {
            headerImage = cached
        } else {
            let rendered = NotecastBrandIcon.headerIconImage(
                accentColor: glowActive ? accentColor : nil,
                isActive: isPanelActive
            )
            headerIconCache[iconKey] = rendered
            headerImage = rendered
        }
        if iconView.image !== headerImage {
            iconView.image = headerImage
        }
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

    @objc private func handleHelpTapped() {
        onOpenGuide?()
    }

    @objc private func handleSettingsTapped() {
        onOpenSettings?()
    }

    @objc private func handleHideTapped() {
        onRequestHide?()
    }

    private static func makeHeaderButton(
        symbolName: String,
        accessibilityLabel: String,
        pointSize: CGFloat = 11.5,
        weight: NSFont.Weight = .medium
    ) -> HeaderIconButton {
        let button = HeaderIconButton()
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return button
    }
}

/// Title bar icon button with borderless hover tint, tactile press fade, and bottom active underline indicator.
private final class HeaderIconButton: NSButton {
    var isActiveState = false {
        didSet {
            if isActiveState != oldValue {
                updateVisualState(animated: true)
            }
        }
    }

    var restTintColor: NSColor? {
        didSet { updateVisualState(animated: false) }
    }

    var hoverTintOverride: NSColor? {
        didSet { updateVisualState(animated: false) }
    }

    var activeAccentColor: NSColor = .controlAccentColor {
        didSet { updateVisualState(animated: false) }
    }

    private let activeIndicatorLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        showsBorderOnlyWhileMouseInside = false
        focusRingType = .none
        bezelStyle = .regularSquare
        imageScaling = .scaleProportionallyDown
        (cell as? NSButtonCell)?.highlightsBy = []
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil

        activeIndicatorLayer.cornerRadius = 1
        activeIndicatorLayer.opacity = 0
        layer?.addSublayer(activeIndicatorLayer)
        updateVisualState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                updateVisualState(animated: false)
            }
        }
    }

    override func layout() {
        super.layout()
        let y: CGFloat = isFlipped ? (bounds.height - 3.5) : 1.5
        activeIndicatorLayer.frame = CGRect(
            x: floor((bounds.width - 10) * 0.5),
            y: y,
            width: 10,
            height: 2
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualState(animated: false)
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
        updateVisualState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateVisualState(animated: true)
    }

    func resetHover() {
        guard isHovered else { return }
        isHovered = false
        updateVisualState(animated: false)
    }

    private func updateVisualState(animated: Bool) {
        let tintColor: NSColor
        let targetAlpha: CGFloat
        let indicatorOpacity: Float

        if isHighlighted {
            targetAlpha = 0.55
            tintColor = isActiveState ? activeAccentColor : (hoverTintOverride ?? .labelColor)
            indicatorOpacity = isActiveState ? 1.0 : 0.0
        } else if isActiveState {
            targetAlpha = 1.0
            tintColor = activeAccentColor
            indicatorOpacity = 1.0
        } else if isHovered {
            targetAlpha = 1.0
            tintColor = hoverTintOverride ?? .labelColor
            indicatorOpacity = 0.0
        } else {
            targetAlpha = 1.0
            tintColor = restTintColor ?? .secondaryLabelColor
            indicatorOpacity = 0.0
        }

        let apply = {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.layer?.borderColor = nil
            self.activeIndicatorLayer.backgroundColor = self.activeAccentColor.cgColor
            self.activeIndicatorLayer.opacity = indicatorOpacity
            self.contentTintColor = tintColor
            self.alphaValue = targetAlpha
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
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

/// Non-interactive subview that delegates all hits to its parent view.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
    var onDragEnded: (() -> Void)?

    private let contrastGradientLayer = CAGradientLayer()
    private let accentGradientLayer = CAGradientLayer()
    private let gripPill = PassThroughView()
    private var trackingArea: NSTrackingArea?

    private var neonGlowEnabled = true
    private var accentColor = NeonAccent.cyan.nsColor
    private var isHovered = false

    private var isTrackingPress = false
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDragDuringPress = false
    private let dragThreshold: CGFloat = 3.0

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
        if !gripPill.bounds.isEmpty {
            gripPill.layer?.shadowPath = CGPath(
                roundedRect: gripPill.bounds,
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil
            )
        }
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

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDragDuringPress = false
        isTrackingPress = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress,
              let window,
              let startMouse = dragStartScreenPoint,
              let startOrigin = dragStartWindowOrigin
        else {
            return
        }

        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y
        if !didDragDuringPress && hypot(dx, dy) >= dragThreshold {
            didDragDuringPress = true
            NSCursor.closedHand.push()
        }
        if didDragDuringPress {
            window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        isTrackingPress = false

        let startMouse = dragStartScreenPoint
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil

        let finalDist: CGFloat
        if let startMouse {
            let currentMouse = NSEvent.mouseLocation
            finalDist = hypot(currentMouse.x - startMouse.x, currentMouse.y - startMouse.y)
        } else {
            finalDist = 0
        }

        if didDragDuringPress || finalDist >= dragThreshold {
            if didDragDuringPress {
                NSCursor.pop()
            }
            didDragDuringPress = false
            onDragEnded?()
            return
        }

        didDragDuringPress = false
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            onWake?()
        }
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

        let stops: [NSNumber] = [0.0, 0.12, 0.30, 0.54, 0.78, 1.0]

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
            ? [0.0, 0.022, 0.065, 0.12, 0.175, 0.22]
            : [0.0, 0.015, 0.045, 0.085, 0.125, 0.16]
        let accentBase = neonGlowEnabled ? accentColor : NSColor.white
        let accentAlphas: [CGFloat] = isHovered
            ? [0.0, 0.018, 0.052, 0.10, 0.165, 0.22]
            : [0.0, 0.012, 0.035, 0.068, 0.105, 0.15]

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
        // Intentionally omit `innerGlowLayer.shadowPath`: CALayer.shadowPath uses non-zero winding
        // and ignores `fillRule = .evenOdd`, which would fill the entire editor interior with shadow.

        let r = bounds.insetBy(dx: 1.0, dy: 1.0)
        let cr = max(2, panelCornerRadius - 1.0)
        let arm: CGFloat = 12
        let gap: CGFloat = 4
        let startX = r.minX + cr + arm + gap
        let endX = r.maxX - cr - arm - gap

        // Top and bottom dotted bars only (left/right vertical dotted bars hidden in Ghost Outline Mode).
        let outlinePath = CGMutablePath()
        if startX < endX {
            outlinePath.move(to: CGPoint(x: startX, y: r.maxY))
            outlinePath.addLine(to: CGPoint(x: endX, y: r.maxY))
            outlinePath.move(to: CGPoint(x: startX, y: r.minY))
            outlinePath.addLine(to: CGPoint(x: endX, y: r.minY))
        }
        ghostContrastOutlineLayer.path = outlinePath
        ghostOutlineLayer.path = outlinePath

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
        ghostCornersLayer.shadowPath = cornersPath.copy(
            strokingWithWidth: ghostCornersLayer.lineWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 4
        )
    }
}

/// Draggable header bar that lets the user reposition the borderless floating panel.
private final class HeaderDragView: NSView {
    var onDragEnded: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        onDragEnded?()
    }
}
