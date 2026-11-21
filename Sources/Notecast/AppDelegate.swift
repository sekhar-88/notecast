import AppKit
import Carbon.HIToolbox
import NotecastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let noteLibrary = NoteLibraryStore()
    private let hotKeyManager = HotKeyManager()

    private var activeNoteID: UUID!
    private var panel: FloatingNotepadPanel!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var previousApp: NSRunningApplication?

    private var toggleMenuItem: NSMenuItem!
    private var backgroundMenuItems: [SurfaceStyle: NSMenuItem] = [:]
    private var neonGlowMenuItem: NSMenuItem!
    private var ghostModeMenuItem: NSMenuItem!
    private var alwaysOnTopMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupPanel()
        setupStatusItem()
        setupHotKey()
        showPanel()
    }

    func applicationWillResignActive(_ notification: Notification) {
        if let activeNoteID {
            try? noteLibrary.flushSync(noteID: activeNoteID, content: panel.textView.string)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activeNoteID {
            try? noteLibrary.flushSync(noteID: activeNoteID, content: panel.textView.string)
        }
        hotKeyManager.teardown()
    }

    // MARK: - Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Notecast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupPanel() {
        let initialFrame = resolvedPanelFrame()

        panel = FloatingNotepadPanel(
            contentRect: initialFrame,
            fontSize: settings.fontSize,
            fontFamily: settings.fontFamily,
            alwaysOnTop: settings.alwaysOnTop,
            followAllSpaces: settings.followAllSpaces,
            surfaceStyle: settings.surfaceStyle,
            opacity: settings.windowOpacity,
            neonGlowEnabled: settings.neonGlowEnabled,
            neonAccent: settings.neonAccent,
            ghostOnUnfocus: settings.ghostOnUnfocus,
            hotKeyHint: settings.hotKey.displayString
        )
        panel.delegate = self

        let initialNote = noteLibrary.lastOpenedNote()
        activeNoteID = initialNote.id
        panel.updateNoteTitle(initialNote.title)
        panel.textView.loadInitialText(noteLibrary.loadContent(for: initialNote.id))

        panel.textView.onTextChanged = { [weak self] updatedText in
            guard let self, let noteID = self.activeNoteID else { return }
            self.panel.updateSaveStatus("Edited")
            let liveTitle = NoteLibraryStore.extractTitleAndPreview(from: updatedText).title
            self.panel.updateNoteTitle(liveTitle)

            self.noteLibrary.scheduleSave(noteID: noteID, content: updatedText) { [weak self] savedMeta in
                DispatchQueue.main.async {
                    guard let self, self.activeNoteID == savedMeta.id else { return }
                    self.panel.updateSaveStatus("Saved")
                    self.panel.updateNoteTitle(savedMeta.title)
                }
            }
        }

        panel.textView.onFontSizeDelta = { [weak self] delta in
            guard let self else { return }
            self.updateFontSize(self.settings.fontSize + delta)
        }

        panel.textView.onFontSizeReset = { [weak self] in
            self?.updateFontSize(AppSettings.defaultFontSize)
        }

        panel.textView.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        panel.textView.onOpenSearch = { [weak self] in
            self?.toggleCommandPalette(mode: .all)
        }

        panel.textView.onOpenNotesSearch = { [weak self] in
            self?.toggleCommandPalette(mode: .notesOnly)
        }

        panel.textView.onNewNote = { [weak self] in
            self?.createNewNote()
        }

        panel.textView.onToggleNotesList = { [weak self] in
            self?.toggleNotesList()
        }

        panel.onTogglePin = { [weak self] in
            guard let self else { return }
            self.updateAlwaysOnTop(!self.settings.alwaysOnTop)
        }

        panel.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        panel.onRequestHide = { [weak self] in
            self?.hidePanel()
        }

        panel.onNewNote = { [weak self] in
            self?.createNewNote()
        }

        panel.onToggleNotesList = { [weak self] in
            self?.toggleNotesList()
        }

        panel.onToggleCommandPalette = { [weak self] in
            self?.toggleCommandPalette(mode: .all)
        }

        panel.onToggleNotesSearch = { [weak self] in
            self?.toggleCommandPalette(mode: .notesOnly)
        }

        panel.onShouldAllowGhostMode = { [weak self] in
            !(self?.settingsController?.window?.isVisible ?? false)
        }

        panel.onWakeFromGhost = { [weak self] in
            self?.showPanel()
        }

        panel.notesListView.onSelectNote = { [weak self] noteID in
            self?.openNote(id: noteID)
        }

        panel.notesListView.onDeleteNote = { [weak self] noteID in
            self?.deleteNote(id: noteID)
        }

        panel.notesListView.onNewNote = { [weak self] in
            self?.createNewNote()
        }

        panel.notesListView.onDismiss = { [weak self] in
            self?.panel.hideNotesList()
        }

        panel.commandPaletteView.queryProvider = { [weak self] query, mode in
            guard let self else { return [] }
            let matchingNotes = self.noteLibrary.searchNotes(query: query)
            return CommandPaletteSearch.results(query: query, matchingNotes: matchingNotes, mode: mode)
        }

        panel.commandPaletteView.onSelectEntry = { [weak self] entry in
            guard let self else { return }
            switch entry {
            case .note(let note):
                self.openNote(id: note.id)
            case .command(let command):
                self.panel.hideCommandPalette()
                self.executeCommand(command.id)
            }
        }

        panel.commandPaletteView.onDismiss = { [weak self] in
            self?.panel.hideCommandPalette()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Notecast")
            button.image?.isTemplate = true
            button.toolTip = "Notecast (\(settings.hotKey.displayString))"
        }

        let menu = NSMenu()
        menu.delegate = self

        toggleMenuItem = NSMenuItem(
            title: "Show Notecast",
            action: #selector(handleToggleFromMenu),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())

        let newNoteItem = NSMenuItem(
            title: "New Note",
            action: #selector(handleNewNoteFromMenu),
            keyEquivalent: "n"
        )
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        let notesListItem = NSMenuItem(
            title: "Notes List",
            action: #selector(handleNotesListFromMenu),
            keyEquivalent: "l"
        )
        notesListItem.target = self
        menu.addItem(notesListItem)

        let searchItem = NSMenuItem(
            title: "Search & Commands",
            action: #selector(handleCommandPaletteFromMenu),
            keyEquivalent: "p"
        )
        searchItem.target = self
        menu.addItem(searchItem)

        let searchNotesItem = NSMenuItem(
            title: "Search Notes",
            action: #selector(handleNotesSearchFromMenu),
            keyEquivalent: "P"
        )
        searchNotesItem.keyEquivalentModifierMask = [.command, .shift]
        searchNotesItem.target = self
        menu.addItem(searchNotesItem)

        menu.addItem(.separator())

        let backgroundItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        let backgroundSubmenu = NSMenu()
        backgroundMenuItems.removeAll()
        for style in SurfaceStyle.allCases {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(handleSelectBackgroundFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            backgroundSubmenu.addItem(item)
            backgroundMenuItems[style] = item
        }
        backgroundItem.submenu = backgroundSubmenu
        menu.addItem(backgroundItem)

        neonGlowMenuItem = NSMenuItem(
            title: "Neon Active Glow",
            action: #selector(handleToggleNeonGlowFromMenu),
            keyEquivalent: ""
        )
        neonGlowMenuItem.target = self
        menu.addItem(neonGlowMenuItem)

        ghostModeMenuItem = NSMenuItem(
            title: "Ghost Outline When Unfocused",
            action: #selector(handleToggleGhostModeFromMenu),
            keyEquivalent: ""
        )
        ghostModeMenuItem.target = self
        menu.addItem(ghostModeMenuItem)

        alwaysOnTopMenuItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(handleToggleAlwaysOnTopFromMenu),
            keyEquivalent: ""
        )
        alwaysOnTopMenuItem.target = self
        menu.addItem(alwaysOnTopMenuItem)

        menu.addItem(.separator())

        let revealItem = NSMenuItem(
            title: "Reveal Notes Folder in Finder",
            action: #selector(revealNotesFolderInFinder),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Notecast",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupHotKey() {
        hotKeyManager.onHotKeyPressed = { [weak self] in
            self?.togglePanel()
        }
        let status = hotKeyManager.register(settings.hotKey)
        if status != noErr {
            if settings.hotKey != .defaultToggle {
                _ = hotKeyManager.register(.defaultToggle)
            }
        }
    }

    // MARK: - Panel Show / Hide

    func togglePanel() {
        if panel.isVisible && !panel.isGhosted {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            previousApp = frontmost
        }

        let clampedFrame = resolvedPanelFrame(preferCurrentFrame: true)
        panel.setFrame(clampedFrame, display: false)
        panel.setGhosted(false, animated: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.dismissOverlaysAndFocusEditor()
    }

    private func hidePanel() {
        if let activeNoteID {
            try? noteLibrary.flushSync(noteID: activeNoteID, content: panel.textView.string)
        }
        panel.updateSaveStatus("Saved")
        panel.orderOut(nil)
        panel.setGhosted(false, animated: false)

        let settingsVisible = settingsController?.window?.isVisible ?? false
        if NSApp.isActive, !settingsVisible {
            previousApp?.activate(options: [])
        }
    }

    // MARK: - Notes & Command Palette Actions

    private func flushActiveNoteSync() {
        guard let activeNoteID else { return }
        try? noteLibrary.flushSync(noteID: activeNoteID, content: panel.textView.string)
    }

    private func openNote(id: UUID) {
        flushActiveNoteSync()
        noteLibrary.setLastOpenedNote(id)
        activeNoteID = id

        let content = noteLibrary.loadContent(for: id)
        let title = NoteLibraryStore.extractTitleAndPreview(from: content).title
        panel.updateNoteTitle(title)
        panel.updateSaveStatus("Saved")
        panel.textView.loadInitialText(content)
        panel.dismissOverlaysAndFocusEditor()
    }

    private func createNewNote() {
        flushActiveNoteSync()
        do {
            let created = try noteLibrary.createNote(initialContent: "")
            activeNoteID = created.id
            panel.updateNoteTitle(created.title)
            panel.updateSaveStatus("Saved")
            panel.textView.loadInitialText("")
            panel.dismissOverlaysAndFocusEditor()
        } catch {
            NSSound.beep()
        }
    }

    private func deleteNote(id: UUID) {
        if id != activeNoteID {
            flushActiveNoteSync()
        }
        do {
            let nextNote = try noteLibrary.deleteNote(id: id)
            let wasActive = (id == activeNoteID)
            activeNoteID = nextNote.id

            if wasActive {
                let content = noteLibrary.loadContent(for: nextNote.id)
                panel.updateNoteTitle(nextNote.title)
                panel.updateSaveStatus("Saved")
                panel.textView.loadInitialText(content)
            }

            if panel.isNotesListVisible {
                panel.showNotesList(notes: noteLibrary.allNotes(), activeNoteID: activeNoteID)
            }
        } catch {
            NSSound.beep()
        }
    }

    private func toggleNotesList() {
        if panel.isNotesListVisible {
            panel.hideNotesList()
        } else {
            showNotesList()
        }
    }

    private func showNotesList() {
        flushActiveNoteSync()
        panel.showNotesList(notes: noteLibrary.allNotes(), activeNoteID: activeNoteID)
    }

    private func toggleCommandPalette(mode: PaletteMode) {
        if panel.isCommandPaletteVisible && panel.activePaletteMode == mode {
            panel.hideCommandPalette()
        } else {
            flushActiveNoteSync()
            panel.showCommandPalette(mode: mode)
        }
    }

    private func executeCommand(_ id: AppCommandID) {
        switch id {
        case .newNote:
            createNewNote()
        case .searchNotesOnly:
            flushActiveNoteSync()
            panel.showCommandPalette(mode: .notesOnly)
        case .showNotesList:
            showNotesList()
        case .cycleBackgroundTheme:
            updateSurfaceStyle(settings.surfaceStyle.next())
        case .toggleImmersiveBlack:
            let next: SurfaceStyle = settings.surfaceStyle == .immersiveBlack ? .charcoal : .immersiveBlack
            updateSurfaceStyle(next)
        case .toggleNeonGlow:
            updateNeonGlow(!settings.neonGlowEnabled)
        case .cycleNeonAccent:
            if !settings.neonGlowEnabled {
                updateNeonGlow(true)
            }
            updateNeonAccent(settings.neonAccent.next())
        case .toggleGhostMode:
            updateGhostOnUnfocus(!settings.ghostOnUnfocus)
        case .toggleAlwaysOnTop:
            updateAlwaysOnTop(!settings.alwaysOnTop)
        case .toggleFollowSpaces:
            updateFollowAllSpaces(!settings.followAllSpaces)
        case .increaseFontSize:
            updateFontSize(settings.fontSize + 1)
        case .decreaseFontSize:
            updateFontSize(settings.fontSize - 1)
        case .resetFontSize:
            updateFontSize(AppSettings.defaultFontSize)
        case .deleteCurrentNote:
            if let activeNoteID {
                deleteNote(id: activeNoteID)
            }
        case .revealNotesFolder:
            revealNotesFolderInFinder()
        case .openSettings:
            openSettings()
        }
    }

    // MARK: - State Synchronization

    private func updateSurfaceStyle(_ style: SurfaceStyle) {
        settings.surfaceStyle = style
        panel.applySurfaceStyle(style, opacity: settings.windowOpacity)
        settingsController?.refreshFromSettings()
    }

    private func updateOpacity(_ opacity: Double) {
        settings.windowOpacity = opacity
        panel.applySurfaceStyle(settings.surfaceStyle, opacity: settings.windowOpacity)
    }

    private func updateNeonGlow(_ enabled: Bool) {
        settings.neonGlowEnabled = enabled
        panel.applyNeonStyle(enabled: enabled, accent: settings.neonAccent)
        settingsController?.refreshFromSettings()
    }

    private func updateNeonAccent(_ accent: NeonAccent) {
        settings.neonAccent = accent
        panel.applyNeonStyle(enabled: settings.neonGlowEnabled, accent: accent)
        settingsController?.refreshFromSettings()
    }

    private func updateFontFamily(_ family: String) {
        settings.fontFamily = family
        panel.applyFont(family: settings.fontFamily, size: settings.fontSize)
        settingsController?.refreshFromSettings()
    }

    private func updateFontSize(_ size: CGFloat) {
        settings.fontSize = size
        panel.applyFont(family: settings.fontFamily, size: settings.fontSize)
        settingsController?.refreshFromSettings()
    }

    private func updateAlwaysOnTop(_ enabled: Bool) {
        settings.alwaysOnTop = enabled
        panel.applyAlwaysOnTop(enabled)
        settingsController?.refreshFromSettings()
    }

    private func updateFollowAllSpaces(_ enabled: Bool) {
        settings.followAllSpaces = enabled
        panel.applyFollowAllSpaces(enabled)
        settingsController?.refreshFromSettings()
    }

    private func updateGhostOnUnfocus(_ enabled: Bool) {
        settings.ghostOnUnfocus = enabled
        panel.applyGhostOnUnfocus(enabled)
        settingsController?.refreshFromSettings()
    }

    private func updateHotKey(_ combo: HotKeyCombo) -> OSStatus {
        let status = hotKeyManager.register(combo)
        if status == noErr {
            settings.hotKey = combo
            panel.updateHotKeyHint(combo.displayString)
            statusItem.button?.toolTip = "Notecast (\(combo.displayString))"
        } else {
            _ = hotKeyManager.register(settings.hotKey)
        }
        return status
    }

    private func resolvedPanelFrame(preferCurrentFrame: Bool = false) -> NSRect {
        let screenVisibleFrames = NSScreen.screens.map(\.visibleFrame)
        let fallback = NSScreen.main?.visibleFrame
            ?? screenVisibleFrames.first
            ?? NSRect(x: 100, y: 100, width: 1280, height: 800)

        let candidate: NSRect?
        if preferCurrentFrame, panel != nil {
            candidate = panel.frame
        } else {
            candidate = settings.savedWindowFrame
        }

        if let candidate {
            return WindowFrameClamper.clamp(
                candidate,
                to: screenVisibleFrames.isEmpty ? [fallback] : screenVisibleFrames,
                fallbackVisibleFrame: fallback
            )
        }

        return WindowFrameClamper.defaultFrame(in: fallback)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        settings.savedWindowFrame = panel.frame
    }

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        settings.savedWindowFrame = panel.frame
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let actionWord = (panel.isVisible && !panel.isGhosted) ? "Hide" : "Show"
        toggleMenuItem.title = "\(actionWord) Notecast (\(settings.hotKey.displayString))"
        for (style, item) in backgroundMenuItems {
            item.state = (style == settings.surfaceStyle) ? .on : .off
        }
        neonGlowMenuItem.state = settings.neonGlowEnabled ? .on : .off
        ghostModeMenuItem.state = settings.ghostOnUnfocus ? .on : .off
        alwaysOnTopMenuItem.state = settings.alwaysOnTop ? .on : .off
    }

    // MARK: - Menu Actions

    @objc private func handleToggleFromMenu() {
        togglePanel()
    }

    @objc private func handleNewNoteFromMenu() {
        if !panel.isVisible || panel.isGhosted {
            showPanel()
        }
        createNewNote()
    }

    @objc private func handleNotesListFromMenu() {
        if !panel.isVisible || panel.isGhosted {
            showPanel()
        }
        showNotesList()
    }

    @objc private func handleCommandPaletteFromMenu() {
        if !panel.isVisible || panel.isGhosted {
            showPanel()
        }
        flushActiveNoteSync()
        panel.showCommandPalette(mode: .all)
    }

    @objc private func handleNotesSearchFromMenu() {
        if !panel.isVisible || panel.isGhosted {
            showPanel()
        }
        flushActiveNoteSync()
        panel.showCommandPalette(mode: .notesOnly)
    }

    @objc private func handleSelectBackgroundFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = SurfaceStyle(rawValue: raw)
        else { return }
        updateSurfaceStyle(style)
    }

    @objc private func handleToggleNeonGlowFromMenu() {
        updateNeonGlow(!settings.neonGlowEnabled)
    }

    @objc private func handleToggleGhostModeFromMenu() {
        updateGhostOnUnfocus(!settings.ghostOnUnfocus)
    }

    @objc private func handleToggleAlwaysOnTopFromMenu() {
        updateAlwaysOnTop(!settings.alwaysOnTop)
    }

    @objc private func revealNotesFolderInFinder() {
        flushActiveNoteSync()
        NSWorkspace.shared.open(noteLibrary.directoryURL)
    }

    @objc private func openSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController(
                settings: settings,
                notesDirectoryURL: noteLibrary.directoryURL
            )
            controller.onHotKeyChange = { [weak self] combo in
                self?.updateHotKey(combo) ?? OSStatus(paramErr)
            }
            controller.onRecordingStateChanged = { [weak self] isRecording in
                if isRecording {
                    self?.hotKeyManager.suspend()
                } else {
                    self?.hotKeyManager.resume()
                }
            }
            controller.onSurfaceStyleChanged = { [weak self] style in
                self?.updateSurfaceStyle(style)
            }
            controller.onOpacityChanged = { [weak self] value in
                self?.updateOpacity(value)
            }
            controller.onNeonGlowChanged = { [weak self] enabled in
                self?.updateNeonGlow(enabled)
            }
            controller.onNeonAccentChanged = { [weak self] accent in
                self?.updateNeonAccent(accent)
            }
            controller.onFontFamilyChanged = { [weak self] family in
                self?.updateFontFamily(family)
            }
            controller.onFontSizeChanged = { [weak self] size in
                self?.updateFontSize(size)
            }
            controller.onAlwaysOnTopChanged = { [weak self] enabled in
                self?.updateAlwaysOnTop(enabled)
            }
            controller.onFollowAllSpacesChanged = { [weak self] enabled in
                self?.updateFollowAllSpaces(enabled)
            }
            controller.onGhostOnUnfocusChanged = { [weak self] enabled in
                self?.updateGhostOnUnfocus(enabled)
            }
            controller.onRevealNotesFolder = { [weak self] in
                self?.revealNotesFolderInFinder()
            }
            settingsController = controller
        }

        settingsController?.showAndFocus()
    }
}
