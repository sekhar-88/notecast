import AppKit
import Carbon.HIToolbox
import NotecastCore
import QuartzCore

let panelCornerRadius: CGFloat = 14

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
    private var uiAccent: UIAccent
    private var checkboxStyle: CheckboxStyle
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
        uiAccent: UIAccent,
        checkboxStyle: CheckboxStyle,
        ghostOnUnfocus: Bool,
        ghostWakeZoneFraction: Double,
        hotKeyHint: String
    ) {
        self.surfaceStyle = surfaceStyle
        self.panelOpacity = opacity
        self.neonGlowEnabled = neonGlowEnabled
        self.neonAccent = neonAccent
        self.uiAccent = uiAccent
        self.checkboxStyle = checkboxStyle
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

        let resolvedAccent = uiAccent.effectiveColor(forLightSurface: surfaceStyle.isLight)

        let layoutManager = MarkdownLayoutManager()
        layoutManager.accentColor = resolvedAccent
        layoutManager.checkboxStyle = checkboxStyle
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let editor = MarkdownTextView(
            frame: .zero,
            textContainer: textContainer,
            fontSize: fontSize,
            fontFamily: fontFamily,
            accentColor: resolvedAccent
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
        if styleChanged {
            textView.applyAccentColor(resolvedUIAccentColor)
        }
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

    private var resolvedUIAccentColor: NSColor {
        uiAccent.effectiveColor(forLightSurface: surfaceStyle.isLight)
    }

    func applyUIAccent(_ accent: UIAccent) {
        self.uiAccent = accent
        textView.applyAccentColor(resolvedUIAccentColor)
        refreshHeaderButtonsTheme()
    }

    func applyCheckboxStyle(_ style: CheckboxStyle) {
        self.checkboxStyle = style
        textView.applyCheckboxStyle(style)
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
        let paletteWasVisible = !commandPaletteView.isHidden
        commandPaletteView.isHidden = true
        if paletteWasVisible {
            onCommandPaletteHidden?()
        }
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
        let accent: NSColor = resolvedUIAccentColor
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
