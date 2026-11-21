import AppKit
import NotecastCore
import ServiceManagement

/// Native macOS Preferences window for Notecast.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate {
    var onHotKeyChange: ((HotKeyCombo) -> OSStatus)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    var onSurfaceStyleChanged: ((SurfaceStyle) -> Void)?
    var onOpacityChanged: ((Double) -> Void)?
    var onNeonGlowChanged: ((Bool) -> Void)?
    var onNeonAccentChanged: ((NeonAccent) -> Void)?
    var onFontFamilyChanged: ((String) -> Void)?
    var onFontFamilyPreview: ((String) -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onFollowAllSpacesChanged: ((Bool) -> Void)?
    var onGhostOnUnfocusChanged: ((Bool) -> Void)?
    var onGhostWakeZoneFractionChanged: ((Double, Bool) -> Void)?
    var onRevealNotesFolder: (() -> Void)?
    var onDidClose: (() -> Void)?

    private let settings: AppSettings
    private let notesDirectoryURL: URL

    private let hotKeyRecorder: HotKeyRecorderControl
    private let hotKeyStatusLabel = NSTextField(labelWithString: "")
    private let backgroundPaletteView = BackgroundPaletteView()
    private let opacitySlider = NSSlider(value: 0.96, minValue: AppSettings.minOpacity, maxValue: AppSettings.maxOpacity, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "96%")
    private let neonGlowCheckbox = NSButton(checkboxWithTitle: "Neon glow when active", target: nil, action: nil)
    private let neonAccentPopup = NSPopUpButton()
    private let fontFamilyPopup = NSPopUpButton()
    private let fontSizeStepper = NSStepper()
    private let fontSizeValueLabel = NSTextField(labelWithString: "14 pt")
    private let alwaysOnTopCheckbox = NSButton(checkboxWithTitle: "Always on top of other windows", target: nil, action: nil)
    private let followSpacesCheckbox = NSButton(checkboxWithTitle: "Float across all Spaces & full-screen apps", target: nil, action: nil)
    private let ghostOnUnfocusCheckbox = NSButton(checkboxWithTitle: "Transparent outline when unfocused", target: nil, action: nil)
    private let ghostWakeZoneSlider = NSSlider(
        value: AppSettings.defaultGhostWakeZoneFraction,
        minValue: AppSettings.minGhostWakeZoneFraction,
        maxValue: AppSettings.maxGhostWakeZoneFraction,
        target: nil,
        action: nil
    )
    private let ghostWakeZoneValueLabel = NSTextField(labelWithString: "45%")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch Notecast at login", target: nil, action: nil)
    private let launchNoteLabel = NSTextField(labelWithString: "")

    private var fontFamilyBeforeMenuOpen: String?
    private var didCommitFontSelection = false

    init(settings: AppSettings, notesDirectoryURL: URL) {
        self.settings = settings
        self.notesDirectoryURL = notesDirectoryURL
        self.hotKeyRecorder = HotKeyRecorderControl(combo: settings.hotKey)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notecast Settings"
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        buildUI()
        wireControls()
        refreshFromSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus(avoiding panelFrame: NSRect? = nil) {
        refreshFromSettings()
        if let window {
            window.layoutIfNeeded()
            if let panelFrame {
                let matchingScreen = NSScreen.screens.first { $0.frame.intersects(panelFrame) }
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
                if let visibleFrame = matchingScreen?.visibleFrame {
                    let origin = WindowFrameClamper.settingsOrigin(
                        for: window.frame.size,
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

    func refreshFromSettings() {
        hotKeyRecorder.combo = settings.hotKey
        backgroundPaletteView.selectedStyle = settings.surfaceStyle

        let isOpaque = settings.surfaceStyle.isOpaque
        opacitySlider.isEnabled = !isOpaque
        opacitySlider.doubleValue = settings.windowOpacity
        if isOpaque {
            opacityValueLabel.stringValue = "100% (Opaque)"
        } else {
            opacityValueLabel.stringValue = "\(Int((settings.windowOpacity * 100).rounded()))%"
        }

        neonGlowCheckbox.state = settings.neonGlowEnabled ? .on : .off
        neonAccentPopup.isEnabled = settings.neonGlowEnabled
        if let accentIndex = NeonAccent.allCases.firstIndex(of: settings.neonAccent) {
            neonAccentPopup.selectItem(at: accentIndex)
        }

        selectFontFamilyItem(settings.fontFamily)

        fontSizeStepper.doubleValue = Double(settings.fontSize)
        fontSizeValueLabel.stringValue = "\(Int(settings.fontSize)) pt"

        alwaysOnTopCheckbox.state = settings.alwaysOnTop ? .on : .off
        followSpacesCheckbox.state = settings.followAllSpaces ? .on : .off
        ghostOnUnfocusCheckbox.state = settings.ghostOnUnfocus ? .on : .off
        ghostWakeZoneSlider.isEnabled = settings.ghostOnUnfocus
        ghostWakeZoneSlider.doubleValue = settings.ghostWakeZoneFraction
        ghostWakeZoneValueLabel.stringValue = "\(Int((settings.ghostWakeZoneFraction * 100).rounded()))%"

        refreshLaunchAtLoginState()
    }

    func windowWillClose(_ notification: Notification) {
        hotKeyRecorder.cancelRecordingIfNeeded()
        hotKeyStatusLabel.stringValue = ""
        onGhostWakeZoneFractionChanged?(settings.ghostWakeZoneFraction, false)
        onDidClose?()
    }

    // MARK: - Layout

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.xPlacement = .leading
        grid.yPlacement = .center

        // 1. Hotkey row
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(handleResetHotKey))
        resetButton.bezelStyle = .rounded
        let hotKeyRow = NSStackView(views: [hotKeyRecorder, resetButton])
        hotKeyRow.orientation = .horizontal
        hotKeyRow.spacing = 8

        hotKeyStatusLabel.font = NSFont.systemFont(ofSize: 11)
        hotKeyStatusLabel.textColor = .systemRed
        hotKeyStatusLabel.maximumNumberOfLines = 2
        hotKeyStatusLabel.preferredMaxLayoutWidth = 280

        let hotKeyStack = NSStackView(views: [hotKeyRow, hotKeyStatusLabel])
        hotKeyStack.orientation = .vertical
        hotKeyStack.alignment = .leading
        hotKeyStack.spacing = 4
        grid.addRow(with: [makeTitleLabel("Global Hotkey:"), hotKeyStack])

        // 2. Background theme swatch palette
        grid.addRow(with: [makeTitleLabel("Background:"), backgroundPaletteView])
        grid.row(at: 1).yPlacement = .top

        // 3. Opacity slider
        opacitySlider.isContinuous = true
        opacityValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        opacityValueLabel.textColor = .secondaryLabelColor
        opacityValueLabel.alignment = .left
        NSLayoutConstraint.activate([
            opacitySlider.widthAnchor.constraint(equalToConstant: 155),
            opacityValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        let opacityRow = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 8
        grid.addRow(with: [makeTitleLabel("Opacity:"), opacityRow])

        // 4. Neon Glow + Accent
        neonAccentPopup.removeAllItems()
        for accent in NeonAccent.allCases {
            neonAccentPopup.addItem(withTitle: accent.displayName)
        }
        let neonRow = NSStackView(views: [neonGlowCheckbox, neonAccentPopup])
        neonRow.orientation = .horizontal
        neonRow.spacing = 10
        grid.addRow(with: [makeTitleLabel("Neon Glow:"), neonRow])

        // 5. Font Family
        populateFontPopup()
        NSLayoutConstraint.activate([
            fontFamilyPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 210)
        ])
        grid.addRow(with: [makeTitleLabel("Font:"), fontFamilyPopup])

        // 6. Font Size
        fontSizeStepper.minValue = Double(AppSettings.minFontSize)
        fontSizeStepper.maxValue = Double(AppSettings.maxFontSize)
        fontSizeStepper.increment = 1
        fontSizeStepper.valueWraps = false
        fontSizeValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        fontSizeValueLabel.alignment = .left
        let fontSizeRow = NSStackView(views: [fontSizeValueLabel, fontSizeStepper])
        fontSizeRow.orientation = .horizontal
        fontSizeRow.spacing = 8
        grid.addRow(with: [makeTitleLabel("Font Size:"), fontSizeRow])

        // 7. Window behavior checkboxes
        let behaviorStack = NSStackView(views: [alwaysOnTopCheckbox, followSpacesCheckbox, ghostOnUnfocusCheckbox])
        behaviorStack.orientation = .vertical
        behaviorStack.alignment = .leading
        behaviorStack.spacing = 6
        grid.addRow(with: [makeTitleLabel("Window:"), behaviorStack])

        // 8. Ghost Wake Area slider
        ghostWakeZoneSlider.isContinuous = true
        ghostWakeZoneValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ghostWakeZoneValueLabel.textColor = .secondaryLabelColor
        ghostWakeZoneValueLabel.alignment = .left
        NSLayoutConstraint.activate([
            ghostWakeZoneSlider.widthAnchor.constraint(equalToConstant: 155),
            ghostWakeZoneValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        let ghostWakeRow = NSStackView(views: [ghostWakeZoneSlider, ghostWakeZoneValueLabel])
        ghostWakeRow.orientation = .horizontal
        ghostWakeRow.spacing = 8
        grid.addRow(with: [makeTitleLabel("Ghost Wake Area:"), ghostWakeRow])

        // 8. Launch at login
        launchNoteLabel.font = NSFont.systemFont(ofSize: 11)
        launchNoteLabel.textColor = .secondaryLabelColor
        let launchStack = NSStackView(views: [launchAtLoginCheckbox, launchNoteLabel])
        launchStack.orientation = .vertical
        launchStack.alignment = .leading
        launchStack.spacing = 2
        grid.addRow(with: [makeTitleLabel("Startup:"), launchStack])

        // 9. Notes folder + Reveal
        let pathLabel = NSTextField(labelWithString: abbreviateHomePath(notesDirectoryURL.path))
        pathLabel.font = NSFont.systemFont(ofSize: 11.5)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.toolTip = notesDirectoryURL.path
        NSLayoutConstraint.activate([
            pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 195)
        ])

        let revealButton = NSButton(title: "Reveal in Finder", target: self, action: #selector(handleRevealInFinder))
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .small
        let fileRow = NSStackView(views: [pathLabel, revealButton])
        fileRow.orientation = .horizontal
        fileRow.spacing = 8
        grid.addRow(with: [makeTitleLabel("Notes Folder:"), fileRow])

        grid.column(at: 0).xPlacement = .trailing

        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func populateFontPopup() {
        fontFamilyPopup.removeAllItems()
        guard let menu = fontFamilyPopup.menu else { return }

        for (id, label) in MarkdownStyler.curatedFontFamilies {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.representedObject = id
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let curatedIDs = Set(MarkdownStyler.curatedFontFamilies.map(\.id))
        let systemFamilies = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !curatedIDs.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        for family in systemFamilies {
            let item = NSMenuItem(title: family, action: nil, keyEquivalent: "")
            item.representedObject = family
            menu.addItem(item)
        }
    }

    private func selectFontFamilyItem(_ familyID: String) {
        if let menu = fontFamilyPopup.menu,
           let item = menu.items.first(where: { ($0.representedObject as? String) == familyID })
        {
            fontFamilyPopup.select(item)
            return
        }
        fontFamilyPopup.selectItem(at: 0)
    }

    private func wireControls() {
        hotKeyRecorder.onRecordingStateChanged = { [weak self] isRecording in
            if isRecording {
                self?.hotKeyStatusLabel.stringValue = ""
            }
            self?.onRecordingStateChanged?(isRecording)
        }

        hotKeyRecorder.onInvalidShortcut = { [weak self] message in
            self?.hotKeyStatusLabel.textColor = .systemOrange
            self?.hotKeyStatusLabel.stringValue = message
        }

        hotKeyRecorder.onHotKeyRecorded = { [weak self] combo in
            self?.applyHotKey(combo)
        }

        backgroundPaletteView.onSelectStyle = { [weak self] style in
            self?.onSurfaceStyleChanged?(style)
        }

        opacitySlider.target = self
        opacitySlider.action = #selector(handleOpacityChanged)

        neonGlowCheckbox.target = self
        neonGlowCheckbox.action = #selector(handleNeonGlowToggled)

        neonAccentPopup.target = self
        neonAccentPopup.action = #selector(handleNeonAccentChanged)

        fontFamilyPopup.target = self
        fontFamilyPopup.action = #selector(handleFontFamilyChanged)
        fontFamilyPopup.menu?.delegate = self

        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(handleFontSizeChanged)

        alwaysOnTopCheckbox.target = self
        alwaysOnTopCheckbox.action = #selector(handleAlwaysOnTopToggled)

        followSpacesCheckbox.target = self
        followSpacesCheckbox.action = #selector(handleFollowSpacesToggled)

        ghostOnUnfocusCheckbox.target = self
        ghostOnUnfocusCheckbox.action = #selector(handleGhostOnUnfocusToggled)

        ghostWakeZoneSlider.target = self
        ghostWakeZoneSlider.action = #selector(handleGhostWakeZoneChanged)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(handleLaunchAtLoginToggled)
    }

    // MARK: - Actions

    @objc private func handleResetHotKey() {
        hotKeyRecorder.cancelRecordingIfNeeded()
        applyHotKey(.defaultToggle)
    }

    private func applyHotKey(_ combo: HotKeyCombo) {
        let status = onHotKeyChange?(combo) ?? noErr
        if status == noErr {
            hotKeyRecorder.combo = combo
            hotKeyStatusLabel.stringValue = ""
        } else {
            hotKeyRecorder.combo = settings.hotKey
            hotKeyStatusLabel.textColor = .systemRed
            hotKeyStatusLabel.stringValue = "Shortcut unavailable or already in use (code \(status))."
        }
    }

    @objc private func handleOpacityChanged() {
        let value = opacitySlider.doubleValue
        opacityValueLabel.stringValue = "\(Int((value * 100).rounded()))%"
        onOpacityChanged?(value)
    }

    @objc private func handleNeonGlowToggled() {
        let enabled = neonGlowCheckbox.state == .on
        neonAccentPopup.isEnabled = enabled
        onNeonGlowChanged?(enabled)
    }

    @objc private func handleNeonAccentChanged() {
        let index = neonAccentPopup.indexOfSelectedItem
        guard index >= 0, index < NeonAccent.allCases.count else { return }
        onNeonAccentChanged?(NeonAccent.allCases[index])
    }

    @objc private func handleFontFamilyChanged() {
        guard let selected = fontFamilyPopup.selectedItem?.representedObject as? String else { return }
        didCommitFontSelection = true
        onFontFamilyChanged?(selected)
    }

    // MARK: - NSMenuDelegate (Live Font Preview)

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === fontFamilyPopup.menu else { return }
        fontFamilyBeforeMenuOpen = settings.fontFamily
        didCommitFontSelection = false
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === fontFamilyPopup.menu,
              let family = item?.representedObject as? String
        else { return }
        onFontFamilyPreview?(family)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === fontFamilyPopup.menu else { return }
        let fallback = fontFamilyBeforeMenuOpen
        fontFamilyBeforeMenuOpen = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didCommitFontSelection, let fallback else { return }
            self.onFontFamilyPreview?(fallback)
        }
    }

    @objc private func handleFontSizeChanged() {
        let size = CGFloat(fontSizeStepper.doubleValue)
        fontSizeValueLabel.stringValue = "\(Int(size)) pt"
        onFontSizeChanged?(size)
    }

    @objc private func handleAlwaysOnTopToggled() {
        onAlwaysOnTopChanged?(alwaysOnTopCheckbox.state == .on)
    }

    @objc private func handleFollowSpacesToggled() {
        onFollowAllSpacesChanged?(followSpacesCheckbox.state == .on)
    }

    @objc private func handleGhostOnUnfocusToggled() {
        let enabled = ghostOnUnfocusCheckbox.state == .on
        ghostWakeZoneSlider.isEnabled = enabled
        onGhostOnUnfocusChanged?(enabled)
    }

    @objc private func handleGhostWakeZoneChanged() {
        let value = ghostWakeZoneSlider.doubleValue
        ghostWakeZoneValueLabel.stringValue = "\(Int((value * 100).rounded()))%"
        let eventType = NSApp.currentEvent?.type
        let isDragging = (eventType == .leftMouseDown || eventType == .leftMouseDragged)
        onGhostWakeZoneFractionChanged?(value, isDragging)
    }

    @objc private func handleLaunchAtLoginToggled() {
        guard isBundledApp else {
            refreshLaunchAtLoginState()
            return
        }
        let enable = launchAtLoginCheckbox.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchNoteLabel.stringValue = ""
        } catch {
            launchNoteLabel.stringValue = "Could not update login item: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginState()
    }

    @objc private func handleRevealInFinder() {
        onRevealNotesFolder?()
    }

    private func refreshLaunchAtLoginState() {
        guard isBundledApp else {
            launchAtLoginCheckbox.state = .off
            launchAtLoginCheckbox.isEnabled = false
            launchNoteLabel.stringValue = "Available when running Notecast.app."
            return
        }

        launchAtLoginCheckbox.isEnabled = true
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            launchAtLoginCheckbox.state = .on
            launchNoteLabel.stringValue = ""
        case .requiresApproval:
            launchAtLoginCheckbox.state = .on
            launchNoteLabel.stringValue = "Approve Notecast in System Settings → Login Items."
        case .notRegistered, .notFound:
            launchAtLoginCheckbox.state = .off
        @unknown default:
            launchAtLoginCheckbox.state = .off
        }
    }

    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func makeTitleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .right
        return label
    }

    private func abbreviateHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
