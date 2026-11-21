import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import NotecastCore

@Suite("NoteStore")
struct NoteStoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notecast-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Atomic save and reload in temp directory")
    func atomicSaveAndReload() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("nested/scratchpad.md")
        let store = NoteStore(fileURL: fileURL, useStarterIfMissing: false)

        try store.flushSync("# Hello\n- [ ] Test unicode 🚀")
        let loaded = store.load()
        #expect(loaded == "# Hello\n- [ ] Test unicode 🚀")

        let reloadStore = NoteStore(fileURL: fileURL, useStarterIfMissing: false)
        #expect(reloadStore.load() == "# Hello\n- [ ] Test unicode 🚀")
    }

    @Test("Debounced scheduleSave writes latest text to disk")
    func debouncedScheduleSave() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("scratchpad.md")
        let store = NoteStore(fileURL: fileURL, useStarterIfMissing: false)

        await withCheckedContinuation { continuation in
            store.scheduleSave("first draft", delay: 0.2)
            store.scheduleSave("final draft", delay: 0.05) {
                continuation.resume()
            }
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content == "final draft")
    }

    @Test("Missing file respects useStarterIfMissing flag")
    func missingFileBehavior() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missingURL = dir.appendingPathComponent("does-not-exist.md")
        let withStarter = NoteStore(fileURL: missingURL, useStarterIfMissing: true)
        #expect(withStarter.load() == NoteStore.defaultStarterContent)

        let emptyMissing = NoteStore(fileURL: missingURL, useStarterIfMissing: false)
        #expect(emptyMissing.load() == "")
    }
}

@Suite("HotKeyCombo")
struct HotKeyComboTests {
    @Test("Default hotkey display string is ⌥ Space")
    func defaultDisplayString() {
        #expect(HotKeyCombo.defaultToggle.displayString == "⌥ Space")
    }

    @Test("Validates modifier and key combinations")
    func validation() {
        let cmdShiftN = HotKeyCombo.from(
            keyCode: UInt16(kVK_ANSI_N),
            modifierFlags: [.command, .shift]
        )
        #expect(cmdShiftN != nil)
        #expect(cmdShiftN?.displayString == "⇧⌘N")

        let optSpace = HotKeyCombo.from(
            keyCode: UInt16(kVK_Space),
            modifierFlags: [.option]
        )
        #expect(optSpace == .defaultToggle)

        let ctrlOptK = HotKeyCombo.from(
            keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: [.control, .option]
        )
        #expect(ctrlOptK?.displayString == "⌃⌥K")

        let f5 = HotKeyCombo.from(keyCode: UInt16(kVK_F5), modifierFlags: [])
        #expect(f5?.displayString == "F5")

        // Reject bare keys, Shift-only letters, modifier-only keys, and Esc
        #expect(HotKeyCombo.from(keyCode: UInt16(kVK_ANSI_A), modifierFlags: []) == nil)
        #expect(HotKeyCombo.from(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.shift]) == nil)
        #expect(HotKeyCombo.from(keyCode: UInt16(kVK_Command), modifierFlags: [.command]) == nil)
        #expect(HotKeyCombo.from(keyCode: UInt16(kVK_Escape), modifierFlags: [.command]) == nil)
    }

    @Test("Codable round-trip preserves keyCode and modifiers")
    func codableRoundTrip() throws {
        let original = HotKeyCombo(
            keyCode: UInt32(kVK_ANSI_N),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("MarkdownEditing")
struct MarkdownEditingTests {
    private func apply(_ result: MarkdownEditing.EditResult, to text: String) -> String {
        (text as NSString).replacingCharacters(in: result.replacementRange, with: result.replacementText)
    }

    @Test("Enter continues unordered, ordered, and checklist items")
    func newlineContinuation() {
        let bulletText = "- item"
        let bulletEdit = MarkdownEditing.handleNewline(in: bulletText, selection: NSRange(location: 6, length: 0))
        #expect(bulletEdit != nil)
        #expect(apply(bulletEdit!, to: bulletText) == "- item\n- ")
        #expect(bulletEdit?.newSelection == NSRange(location: 9, length: 0))

        let starText = "  * nested"
        let starEdit = MarkdownEditing.handleNewline(in: starText, selection: NSRange(location: 10, length: 0))
        #expect(apply(starEdit!, to: starText) == "  * nested\n  * ")

        let orderedText = "1. first"
        let orderedEdit = MarkdownEditing.handleNewline(in: orderedText, selection: NSRange(location: 8, length: 0))
        #expect(apply(orderedEdit!, to: orderedText) == "1. first\n2. ")

        let todoText = "- [ ] task"
        let todoEdit = MarkdownEditing.handleNewline(in: todoText, selection: NSRange(location: 10, length: 0))
        #expect(apply(todoEdit!, to: todoText) == "- [ ] task\n- [ ] ")

        let doneText = "- [x] done"
        let doneEdit = MarkdownEditing.handleNewline(in: doneText, selection: NSRange(location: 10, length: 0))
        #expect(apply(doneEdit!, to: doneText) == "- [x] done\n- [ ] ")
    }

    @Test("Enter on empty list prefix exits list cleanly")
    func newlineExitsEmptyList() {
        let emptyBullet = "- "
        let exitBullet = MarkdownEditing.handleNewline(in: emptyBullet, selection: NSRange(location: 2, length: 0))
        #expect(exitBullet != nil)
        #expect(apply(exitBullet!, to: emptyBullet) == "")
        #expect(exitBullet?.newSelection == NSRange(location: 0, length: 0))

        let emptyTask = "first\n- [ ] "
        let exitTask = MarkdownEditing.handleNewline(in: emptyTask, selection: NSRange(location: 12, length: 0))
        #expect(exitTask != nil)
        #expect(apply(exitTask!, to: emptyTask) == "first\n")
        #expect(exitTask?.newSelection == NSRange(location: 6, length: 0))
    }

    @Test("Inline wrapper wraps, unwraps, and inserts empty marker pairs")
    func inlineWrapper() {
        // Wrap selection
        let plain = "hello world"
        let wrap = MarkdownEditing.toggleWrapper(in: plain, selection: NSRange(location: 6, length: 5), marker: "**")
        #expect(apply(wrap, to: plain) == "hello **world**")
        #expect(wrap.newSelection == NSRange(location: 8, length: 5))

        // Unwrap when markers included in selection
        let bolded = "hello **world**"
        let unwrapOuter = MarkdownEditing.toggleWrapper(in: bolded, selection: NSRange(location: 6, length: 9), marker: "**")
        #expect(apply(unwrapOuter, to: bolded) == "hello world")
        #expect(unwrapOuter.newSelection == NSRange(location: 6, length: 5))

        // Unwrap when markers surround selection
        let unwrapInner = MarkdownEditing.toggleWrapper(in: bolded, selection: NSRange(location: 8, length: 5), marker: "**")
        #expect(apply(unwrapInner, to: bolded) == "hello world")
        #expect(unwrapInner.newSelection == NSRange(location: 6, length: 5))

        // Empty selection inserts pair and places cursor inside
        let emptyWrap = MarkdownEditing.toggleWrapper(in: plain, selection: NSRange(location: 5, length: 0), marker: "`")
        #expect(apply(emptyWrap, to: plain) == "hello`` world")
        #expect(emptyWrap.newSelection == NSRange(location: 6, length: 0))

        // Strikethrough
        let strike = MarkdownEditing.toggleWrapper(in: plain, selection: NSRange(location: 0, length: 5), marker: "~~")
        #expect(apply(strike, to: plain) == "~~hello~~ world")

        // Italic inside bold produces ***word*** instead of stripping a bold star
        let italicInsideBold = MarkdownEditing.toggleWrapper(in: bolded, selection: NSRange(location: 8, length: 5), marker: "*")
        #expect(apply(italicInsideBold, to: bolded) == "hello ***world***")
    }

    @Test("Toggle checklist cycles plain, list, unchecked, and checked states")
    func toggleChecklistLine() {
        let s1 = "buy milk"
        let r1 = MarkdownEditing.toggleChecklist(in: s1, selection: NSRange(location: 8, length: 0))
        let s2 = apply(r1, to: s1)
        #expect(s2 == "- [ ] buy milk")

        let r2 = MarkdownEditing.toggleChecklist(in: s2, selection: r1.newSelection)
        let s3 = apply(r2, to: s2)
        #expect(s3 == "- [x] buy milk")

        let r3 = MarkdownEditing.toggleChecklist(in: s3, selection: r2.newSelection)
        let s4 = apply(r3, to: s3)
        #expect(s4 == "- [ ] buy milk")

        let bullet = "- foo"
        let rBullet = MarkdownEditing.toggleChecklist(in: bullet, selection: NSRange(location: 5, length: 0))
        #expect(apply(rBullet, to: bullet) == "- [ ] foo")
    }

    @Test("Click toggle flips checkbox only when index is inside brackets")
    func toggleCheckboxAtIndex() {
        let text = "- [ ] ship v1"
        // Indices: '-' (0), ' ' (1), '[' (2), ' ' (3), ']' (4), ' ' (5), 's' (6)
        #expect(MarkdownEditing.toggleCheckboxAtCharacterIndex(0, in: text) == nil)
        #expect(MarkdownEditing.toggleCheckboxAtCharacterIndex(6, in: text) == nil)

        let check = MarkdownEditing.toggleCheckboxAtCharacterIndex(3, in: text)
        #expect(check != nil)
        let checkedText = apply(check!, to: text)
        #expect(checkedText == "- [x] ship v1")

        let uncheck = MarkdownEditing.toggleCheckboxAtCharacterIndex(2, in: checkedText)
        #expect(uncheck != nil)
        #expect(apply(uncheck!, to: checkedText) == "- [ ] ship v1")
    }

    @Test("Indent and outdent adjust single and multi-line selections")
    func adjustIndentation() {
        let text = "- one\n- two"
        let indent = MarkdownEditing.adjustIndentation(in: text, selection: NSRange(location: 0, length: 11), outdent: false)
        #expect(indent != nil)
        let indented = apply(indent!, to: text)
        #expect(indented == "  - one\n  - two")

        let outdent = MarkdownEditing.adjustIndentation(in: indented, selection: indent!.newSelection, outdent: true)
        #expect(outdent != nil)
        #expect(apply(outdent!, to: indented) == text)
    }
}

@Suite("MarkdownStyler")
struct MarkdownStylerTests {
    @Test("Heading scales font size and dims hash prefix")
    func headingStyling() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let storage = NSTextStorage(string: "# Title")
        styler.styleAll(storage)

        let hashColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let titleFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont

        #expect(hashColor == .tertiaryLabelColor)
        #expect((titleFont?.pointSize ?? 0) > 14)
    }

    @Test("Inline bold, italic, and snake_case preservation")
    func inlineBoldItalicAndSnakeCase() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "**bold** and *italic* and foo_bar_baz"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        // 'b' in **bold** at index 2
        let boldFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        // 'i' in *italic* at index 14
        let italicFont = storage.attribute(.font, at: 14, effectiveRange: nil) as? NSFont
        #expect(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)

        // 'b' in foo_bar_baz should NOT be italic
        let nsText = text as NSString
        let snakeIdx = nsText.range(of: "bar").location
        let snakeFont = storage.attribute(.font, at: snakeIdx, effectiveRange: nil) as? NSFont
        #expect(snakeFont?.fontDescriptor.symbolicTraits.contains(.italic) == false)
    }

    @Test("Inline code uses monospaced font")
    func inlineCodeStyling() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "Run `swift test` now"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let codeIdx = (text as NSString).range(of: "swift").location
        let codeFont = storage.attribute(.font, at: codeIdx, effectiveRange: nil) as? NSFont
        #expect(codeFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test("Checked checklist items get strikethrough while unchecked items do not")
    func checklistStrikethrough() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "- [x] done\n- [ ] todo"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let nsText = text as NSString
        let doneIdx = nsText.range(of: "done").location
        let todoIdx = nsText.range(of: "todo").location

        let doneStrike = storage.attribute(.strikethroughStyle, at: doneIdx, effectiveRange: nil) as? Int
        let todoStrike = storage.attribute(.strikethroughStyle, at: todoIdx, effectiveRange: nil) as? Int

        #expect(doneStrike == NSUnderlineStyle.single.rawValue)
        #expect(todoStrike == nil || todoStrike == 0)
    }
}

@Suite("WindowFrameClamper")
struct WindowFrameClamperTests {
    private let mainVisible = NSRect(x: 0, y: 0, width: 1512, height: 945)

    @Test("Restores valid on-screen frame untouched")
    func preservesOnScreenFrame() {
        let saved = NSRect(x: 240, y: 180, width: 460, height: 540)
        let result = WindowFrameClamper.clamp(saved, to: [mainVisible], fallbackVisibleFrame: mainVisible)
        #expect(result == saved)
    }

    @Test("Clamps off-screen disconnected monitor frame back into visible fallback frame")
    func recoversOffScreenFrame() {
        let disconnected = NSRect(x: 2600, y: 300, width: 420, height: 500)
        let result = WindowFrameClamper.clamp(disconnected, to: [mainVisible], fallbackVisibleFrame: mainVisible)
        #expect(mainVisible.contains(result))
        #expect(result.size == disconnected.size)
    }

    @Test("Enforces minimum window size")
    func enforcesMinimumSize() {
        let tiny = NSRect(x: 100, y: 100, width: 120, height: 80)
        let result = WindowFrameClamper.clamp(tiny, to: [mainVisible], fallbackVisibleFrame: mainVisible)
        #expect(result.width >= WindowFrameClamper.minSize.width)
        #expect(result.height >= WindowFrameClamper.minSize.height)
    }
}

@Suite("NoteLibraryStore")
struct NoteLibraryStoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notecast-library-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Multi-note creation and lastOpenedNote persistence across reload")
    func multiNoteAndLastOpenedPersistence() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        let first = try store.createNote(initialContent: "# Alpha\nFirst body")
        let second = try store.createNote(initialContent: "# Beta\nSecond body")
        try store.flushSync(noteID: second.id, content: "# Beta Updated\nStill working")

        #expect(store.allNotes().count == 2)
        #expect(store.lastOpenedNote().id == second.id)

        store.setLastOpenedNote(first.id)

        let reloaded = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        #expect(reloaded.lastOpenedNote().id == first.id)
        #expect(reloaded.loadContent(for: second.id) == "# Beta Updated\nStill working")
    }

    @Test("Legacy scratchpad.md migrates into the first note")
    func legacyMigration() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacyURL = dir.appendingPathComponent("scratchpad.md")
        try Data("# Legacy Note\nMigrated text".utf8).write(to: legacyURL)

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: legacyURL, useStarterIfEmpty: true)

        let active = store.lastOpenedNote()
        #expect(active.title == "Legacy Note")
        #expect(store.loadContent(for: active.id) == "# Legacy Note\nMigrated text")
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test("Title and preview extraction strips Markdown syntax and handles empty content")
    func titleAndPreviewExtraction() {
        let extracted = NoteLibraryStore.extractTitleAndPreview(
            from: "\n# **Sprint** `Goals`\n- [ ] Ship `v2` release\nThird line"
        )
        #expect(extracted.title == "Sprint Goals")
        #expect(extracted.preview == "Ship v2 release")

        let blank = NoteLibraryStore.extractTitleAndPreview(from: "   \n  \n")
        #expect(blank.title == "Untitled Note")
        #expect(blank.preview == "")
    }

    @Test("Deleting active note switches to next note and creates fallback when last deleted")
    func deleteNoteBehavior() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        let first = try store.createNote(initialContent: "# First")
        let second = try store.createNote(initialContent: "# Second")

        let afterFirstDelete = try store.deleteNote(id: second.id)
        #expect(afterFirstDelete.id == first.id)
        #expect(store.allNotes().count == 1)

        let fallback = try store.deleteNote(id: first.id)
        #expect(fallback.id != first.id)
        #expect(fallback.title == "Untitled Note")
        #expect(store.allNotes().count == 1)
    }

    @Test("Search matches title and body case-insensitively and ranks title matches first")
    func searchRanking() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        let bodyMatch = try store.createNote(initialContent: "# Grocery List\nBuy neon markers")
        let titleMatch = try store.createNote(initialContent: "# Neon Design Ideas\nBorder glow")

        let results = store.searchNotes(query: "NEON")
        #expect(results.map(\.id) == [titleMatch.id, bodyMatch.id])
    }
}

@Suite("CommandPaletteSearch")
struct CommandPaletteSearchTests {
    private let sampleNotes = [
        NoteMetadata(id: UUID(), title: "Roadmap", preview: "Q4 milestones", createdAt: Date(), updatedAt: Date()),
        NoteMetadata(id: UUID(), title: "Ideas", preview: "Neon theme", createdAt: Date(), updatedAt: Date())
    ]

    @Test("Empty query returns recent notes followed by commands")
    func emptyQuery() {
        let entries = CommandPaletteSearch.results(query: "", matchingNotes: sampleNotes)
        #expect(entries.count == sampleNotes.count + AppCommandDescriptor.all.count)
        if case .note(let firstNote) = entries.first {
            #expect(firstNote.title == "Roadmap")
        } else {
            Issue.record("Expected note entry first")
        }
    }

    @Test("Greater-than prefix filters commands only")
    func commandPrefixFiltering() {
        let entries = CommandPaletteSearch.results(query: ">neon", matchingNotes: sampleNotes)
        #expect(!entries.isEmpty)
        var commandIDs: [AppCommandID] = []
        for entry in entries {
            switch entry {
            case .note:
                Issue.record("Did not expect notes when query starts with '>'")
            case .command(let cmd):
                commandIDs.append(cmd.id)
                #expect(cmd.id == .toggleNeonGlow || cmd.id == .cycleNeonAccent || cmd.id == .openSettings)
            }
        }
        #expect(commandIDs.contains(.toggleNeonGlow))
        #expect(commandIDs.contains(.cycleNeonAccent))
    }

    @Test("Plain query returns matching notes and matching commands")
    func plainQueryMixedResults() {
        let matching = [sampleNotes[1]]
        let entries = CommandPaletteSearch.results(query: "neon", matchingNotes: matching)
        let hasNote = entries.contains {
            if case .note(let n) = $0 { return n.id == sampleNotes[1].id }
            return false
        }
        let hasCommand = entries.contains {
            if case .command(let c) = $0 { return c.id == .toggleNeonGlow }
            return false
        }
        #expect(hasNote)
        #expect(hasCommand)
    }
}

@Suite("AppSettingsAndStyler")
struct AppSettingsAndStylerTests {
    @Test("SurfaceStyle, NeonAccent, and fontFamily round-trip in isolated UserDefaults")
    @MainActor
    func settingsRoundTrip() {
        let suiteName = "notecast.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.surfaceStyle == .immersiveBlack)
        #expect(settings.neonGlowEnabled == true)
        #expect(settings.neonAccent == .cyan)
        #expect(settings.fontFamily == "system")

        settings.surfaceStyle = .translucentHUD
        settings.neonGlowEnabled = false
        settings.neonAccent = .magenta
        settings.fontFamily = "Menlo"

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.surfaceStyle == .translucentHUD)
        #expect(reloaded.neonGlowEnabled == false)
        #expect(reloaded.neonAccent == .magenta)
        #expect(reloaded.fontFamily == "Menlo")
    }

    @Test("MarkdownStyler.resolveFont resolves system, system-mono, Menlo, and unknown fallback")
    func fontResolution() {
        let sys = MarkdownStyler.resolveFont(family: "system", size: 15)
        #expect(sys.pointSize == 15)

        let mono = MarkdownStyler.resolveFont(family: "system-mono", size: 13)
        #expect(mono.fontDescriptor.symbolicTraits.contains(.monoSpace))

        let menlo = MarkdownStyler.resolveFont(family: "Menlo", size: 16)
        #expect(menlo.familyName == "Menlo")
        #expect(menlo.pointSize == 16)

        let fallback = MarkdownStyler.resolveFont(family: "DefinitelyNonExistentFontXYZ_123", size: 14)
        #expect(fallback.pointSize == 14)
    }
}
