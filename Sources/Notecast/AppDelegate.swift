import AppKit
import Carbon.HIToolbox
import NotecastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let noteLibrary = NoteLibraryStore()
    private let hotKeyManager = HotKeyManager()

    private var activeNoteID: UUID!
    private var isActiveNoteReadable = true
    private var isEditorDirty = false
    private var panel: FloatingNotepadPanel!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var guideController: VioletGuideWindowController?
    private var previousApp: NSRunningApplication?
    private var lastSafePanelFrame: NSRect?
    private var screenObserver: NSObjectProtocol?

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
        observeScreenChanges()
        showPanel()

        if !settings.hasSeenOnboardingGuide {
            settings.hasSeenOnboardingGuide = true
            openGuide(mode: .welcome)
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        if panel != nil {
            settings.savedWindowFrame = panel.frame
        }
        flushActiveNoteSync()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if panel != nil {
            settings.savedWindowFrame = panel.frame
        }
        let flushed = flushActiveNoteSync()
        if !flushed || noteLibrary.hasPendingChanges() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to Save Notes"
            alert.informativeText = "Notecast could not write your latest edits to disk. Keep Notecast open to retry or copy your text, or quit anyway."
            alert.addButton(withTitle: "Keep Open")
            alert.addButton(withTitle: "Quit Anyway")
            NSApp.activate()
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if panel != nil {
            settings.savedWindowFrame = panel.frame
        }
        hotKeyManager.teardown()
    }

    // MARK: - Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let guideMenuItem = appMenu.addItem(
            withTitle: "Quick Guide & Shortcuts…",
            action: #selector(handleOpenGuideFromMenu),
            keyEquivalent: "?"
        )
        guideMenuItem.target = self
        let settingsMenuItem = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsMenuItem.target = self
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
        lastSafePanelFrame = initialFrame

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
            uiAccent: settings.uiAccent,
            checkboxStyle: settings.checkboxStyle,
            ghostOnUnfocus: settings.ghostOnUnfocus,
            ghostWakeZoneFraction: settings.ghostWakeZoneFraction,
            hotKeyHint: settings.hotKey.displayString
        )
        panel.delegate = self

        let initialNote = noteLibrary.lastOpenedNote()
        activeNoteID = initialNote.id
        panel.updateNoteTitle(initialNote.title)
        if let loaded = try? noteLibrary.loadContentStrict(for: initialNote.id) {
            isActiveNoteReadable = true
            isEditorDirty = loaded.hasPendingEdits
            panel.textView.isEditable = true
            panel.textView.loadInitialText(loaded.content)
            panel.updateSaveStatus(loaded.hasPendingEdits ? "Edited" : "Saved")
        } else {
            isActiveNoteReadable = false
            isEditorDirty = false
            panel.textView.isEditable = false
            panel.textView.loadInitialText("")
            panel.updateSaveStatus("Read failed")
        }

        panel.textView.onTextChanged = { [weak self] updatedText in
            guard let self, self.isActiveNoteReadable, let noteID = self.activeNoteID else { return }
            self.isEditorDirty = true
            self.panel.updateSaveStatus("Edited")
            let liveTitle = NoteLibraryStore.extractTitle(from: updatedText)
            self.panel.updateNoteTitle(liveTitle)

            self.noteLibrary.scheduleSave(
                noteID: noteID,
                content: updatedText,
                onSaved: { [weak self] savedMeta in
                    DispatchQueue.main.async {
                        guard let self, self.activeNoteID == savedMeta.id else { return }
                        if self.panel.textView.committedText == updatedText {
                            self.isEditorDirty = false
                            self.panel.updateSaveStatus("Saved")
                        }
                        self.panel.updateNoteTitle(savedMeta.title)
                    }
                },
                onError: { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.activeNoteID == noteID else { return }
                        self.panel.updateSaveStatus("Save failed")
                    }
                }
            )
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

        panel.onOpenGuide = { [weak self] in
            self?.openGuide(mode: .instructions)
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
            let settingsOpen = self?.settingsController?.window?.isVisible ?? false
            let guideOpen = self?.guideController?.window?.isVisible ?? false
            return !settingsOpen && !guideOpen
        }

        panel.onWakeFromGhost = { [weak self] in
            self?.showPanel()
        }

        panel.onGhostDragEnded = { [weak self] in
            guard let self else { return }
            self.settings.savedWindowFrame = self.panel.frame
            self.ensureGhostWakeZoneAccessible(animated: true)
        }

        panel.onHeaderDragEnded = { [weak self] in
            guard let self else { return }
            self.settings.savedWindowFrame = self.panel.frame
        }

        panel.onCommandPaletteHidden = { [weak self] in
            self?.noteLibrary.clearSearchCache()
        }

        panel.onShouldEnsureWakeZoneOnScreen = { [weak self] in
            self?.ensureGhostWakeZoneAccessible(animated: true)
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
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if mode == .all && trimmed.hasPrefix(">") {
                return CommandPaletteSearch.results(query: query, matchingNotes: [], mode: mode)
            }
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
            let icon = NotecastBrandIcon.menuBarImage()
            icon.accessibilityDescription = "Notecast"
            icon.isTemplate = true
            button.image = icon
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

        let guideItem = NSMenuItem(
            title: "Quick Guide & Shortcuts",
            action: #selector(handleOpenGuideFromMenu),
            keyEquivalent: "?"
        )
        guideItem.target = self
        menu.addItem(guideItem)

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
        hotKeyManager.onPreferencesHotKeyPressed = { [weak self] in
            self?.openSettings()
        }
        let status = hotKeyManager.register(settings.hotKey)
        if status != noErr {
            if settings.hotKey != .defaultToggle {
                _ = hotKeyManager.register(.defaultToggle)
            }
        }
        _ = hotKeyManager.registerPreferences(.defaultPreferences)
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible && self.panel.isGhosted else { return }
                self.ensureGhostWakeZoneAccessible(animated: true)
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

        // If the active note is clean (no local unsaved edits), pick up any external `.md` changes on disk.
        if isActiveNoteReadable, !isEditorDirty, let activeNoteID,
           let refreshed = try? noteLibrary.loadContentStrict(for: activeNoteID),
           refreshed.content != panel.textView.string
        {
            panel.updateNoteTitle(NoteLibraryStore.extractTitle(from: refreshed.content))
            panel.textView.loadInitialText(refreshed.content)
            panel.updateSaveStatus(refreshed.hasPendingEdits ? "Edited" : "Saved")
        }

        let clampedFrame = resolvedPanelFrame(preferCurrentFrame: true)
        panel.setFrame(clampedFrame, display: false)
        panel.setGhosted(false, animated: true)
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.dismissOverlaysAndFocusEditor()
    }

    private func hidePanel() {
        settings.savedWindowFrame = panel.frame
        let saved = flushActiveNoteSync()
        if isActiveNoteReadable {
            panel.updateSaveStatus(saved ? "Saved" : "Save failed")
        }
        panel.orderOut(nil)
        panel.setGhosted(false, animated: false)

        let settingsVisible = settingsController?.window?.isVisible ?? false
        let guideVisible = guideController?.window?.isVisible ?? false
        if NSApp.isActive, !settingsVisible, !guideVisible {
            previousApp?.activate(options: [])
        }
    }

    // MARK: - Notes & Command Palette Actions

    @discardableResult
    private func flushActiveNoteSync() -> Bool {
        do {
            if isActiveNoteReadable, isEditorDirty, let activeNoteID {
                try noteLibrary.flushSync(noteID: activeNoteID, content: panel.textView.committedText)
                isEditorDirty = false
            } else {
                // Flush any other pending notes or deferred index updates without overwriting
                // a clean (possibly externally edited) or unreadable active note.
                try noteLibrary.flushSync()
            }
            return true
        } catch {
            if isActiveNoteReadable {
                panel.updateSaveStatus("Save failed")
            }
            return false
        }
    }

    private func openNote(id: UUID) {
        flushActiveNoteSync()
        do {
            let loaded = try noteLibrary.loadContentStrict(for: id)
            noteLibrary.setLastOpenedNote(id)
            activeNoteID = id
            isActiveNoteReadable = true
            isEditorDirty = loaded.hasPendingEdits
            panel.textView.isEditable = true

            let title = NoteLibraryStore.extractTitle(from: loaded.content)
            panel.updateNoteTitle(title)
            panel.updateSaveStatus(loaded.hasPendingEdits ? "Edited" : "Saved")
            panel.textView.loadInitialText(loaded.content)
            panel.dismissOverlaysAndFocusEditor()
        } catch {
            panel.updateSaveStatus("Read failed")
            NSSound.beep()
        }
    }

    private func createNewNote() {
        flushActiveNoteSync()
        do {
            let created = try noteLibrary.createNote(initialContent: "")
            activeNoteID = created.id
            isActiveNoteReadable = true
            isEditorDirty = false
            panel.textView.isEditable = true
            panel.updateNoteTitle(created.title)
            panel.updateSaveStatus("Saved")
            panel.textView.loadInitialText("")
            panel.dismissOverlaysAndFocusEditor()
        } catch {
            NSSound.beep()
        }
    }

    private func deleteNote(id: UUID) {
        let wasActive = (id == activeNoteID)
        if !wasActive {
            flushActiveNoteSync()
        }
        do {
            let nextNote = try noteLibrary.deleteNote(id: id)

            if wasActive {
                let loaded = try? noteLibrary.loadContentStrict(for: nextNote.id)
                activeNoteID = nextNote.id
                panel.updateNoteTitle(nextNote.title)
                if let loaded {
                    isActiveNoteReadable = true
                    isEditorDirty = loaded.hasPendingEdits
                    panel.textView.isEditable = true
                    panel.updateSaveStatus(loaded.hasPendingEdits ? "Edited" : "Saved")
                    panel.textView.loadInitialText(loaded.content)
                } else {
                    isActiveNoteReadable = false
                    isEditorDirty = false
                    panel.textView.isEditable = false
                    panel.updateSaveStatus("Read failed")
                    panel.textView.loadInitialText("")
                }
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

    private func updateUIAccent(_ accent: UIAccent) {
        settings.uiAccent = accent
        panel.applyUIAccent(accent)
        settingsController?.refreshFromSettings()
    }

    private func updateCheckboxStyle(_ style: CheckboxStyle) {
        settings.checkboxStyle = style
        panel.applyCheckboxStyle(style)
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
        let wasGhosted = panel.isGhosted
        settings.ghostOnUnfocus = enabled
        panel.applyGhostOnUnfocus(enabled)
        if !enabled && wasGhosted {
            let clamped = resolvedPanelFrame(preferCurrentFrame: true)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: true, animate: true)
                settings.savedWindowFrame = clamped
            }
        }
        settingsController?.refreshFromSettings()
    }

    private func updateGhostWakeZoneFraction(_ fraction: Double, previewOverlay: Bool) {
        settings.ghostWakeZoneFraction = fraction
        panel.applyGhostWakeZoneFraction(fraction, previewOverlay: previewOverlay)
        if !previewOverlay && panel.isGhosted {
            ensureGhostWakeZoneAccessible(animated: true)
        }
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
        recordSafeFrameIfAccessible(panel.frame)
    }

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        recordSafeFrameIfAccessible(panel.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        settings.savedWindowFrame = panel.frame
        recordSafeFrameIfAccessible(panel.frame)
    }

    private func currentVisibleScreenBounds() -> (screens: [NSRect], fallback: NSRect) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallback = NSScreen.main?.visibleFrame
            ?? screens.first
            ?? NSRect(x: 100, y: 100, width: 1280, height: 800)
        return (screens.isEmpty ? [fallback] : screens, fallback)
    }

    private func recordSafeFrameIfAccessible(_ frame: NSRect) {
        let bounds = currentVisibleScreenBounds()
        let checked = WindowFrameClamper.ensureWakeZoneAccessible(
            frame,
            wakeZoneFraction: settings.ghostWakeZoneFraction,
            to: bounds.screens,
            fallbackVisibleFrame: bounds.fallback,
            lastSafeFrame: lastSafePanelFrame
        )
        if checked == frame {
            lastSafePanelFrame = frame
        }
    }

    private func ensureGhostWakeZoneAccessible(animated: Bool) {
        let current = panel.frame
        let bounds = currentVisibleScreenBounds()
        let adjusted = WindowFrameClamper.ensureWakeZoneAccessible(
            current,
            wakeZoneFraction: settings.ghostWakeZoneFraction,
            to: bounds.screens,
            fallbackVisibleFrame: bounds.fallback,
            lastSafeFrame: lastSafePanelFrame
        )
        lastSafePanelFrame = adjusted
        if adjusted != current {
            panel.setFrame(adjusted, display: true, animate: animated)
            settings.savedWindowFrame = adjusted
        }
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
            controller.onUIAccentChanged = { [weak self] accent in
                self?.updateUIAccent(accent)
            }
            controller.onCheckboxStyleChanged = { [weak self] style in
                self?.updateCheckboxStyle(style)
            }
            controller.onFontFamilyChanged = { [weak self] family in
                self?.updateFontFamily(family)
            }
            controller.onFontFamilyPreview = { [weak self] family in
                guard let self else { return }
                self.panel.applyFont(family: family, size: self.settings.fontSize)
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
            controller.onGhostWakeZoneFractionChanged = { [weak self] fraction, isPreviewing in
                self?.updateGhostWakeZoneFraction(fraction, previewOverlay: isPreviewing)
            }
            controller.onRevealNotesFolder = { [weak self] in
                self?.revealNotesFolderInFinder()
            }
            controller.onDidClose = { [weak self] in
                guard let self else { return }
                self.panel.setSettingsActive(false)
                self.hotKeyManager.resume()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.settingsController?.window?.isVisible != true else { return }
                    self.settingsController = nil
                }
            }
            settingsController = controller
        }

        if panel.isVisible && panel.isGhosted {
            panel.setGhosted(false, animated: true)
        }
        panel.setSettingsActive(true)
        settingsController?.showAndFocus(avoiding: panel.isVisible ? panel.frame : nil)
    }

    @objc private func handleOpenGuideFromMenu() {
        openGuide(mode: .instructions)
    }

    private func openGuide(mode: VioletGuideWindowController.Mode) {
        if guideController == nil {
            let controller = VioletGuideWindowController(mode: mode)
            controller.onOpenSettings = { [weak self] in
                self?.openSettings()
            }
            controller.onDismissToEditor = { [weak self] in
                guard let self else { return }
                if self.panel.isVisible {
                    self.panel.makeKeyAndOrderFront(nil)
                    self.panel.dismissOverlaysAndFocusEditor()
                }
            }
            controller.onDidClose = { [weak self] in
                guard let self else { return }
                self.panel.setGuideActive(false)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.guideController?.window?.isVisible != true else { return }
                    self.guideController = nil
                }
            }
            guideController = controller
        }

        if panel.isVisible && panel.isGhosted {
            panel.setGhosted(false, animated: true)
        }
        panel.setGuideActive(true)
        guideController?.show(mode: mode, avoiding: panel.isVisible ? panel.frame : nil)
    }
}
