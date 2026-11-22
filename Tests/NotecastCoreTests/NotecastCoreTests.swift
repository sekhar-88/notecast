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
    @Test("Default hotkey display string is ⌥⌘N and preferences is ⌥⌘,")
    func defaultDisplayString() {
        #expect(HotKeyCombo.defaultToggle.displayString == "⌥⌘N")
        #expect(HotKeyCombo.defaultPreferences.displayString == "⌥⌘,")
    }

    @Test("Validates modifier and key combinations")
    func validation() {
        let cmdShiftN = HotKeyCombo.from(
            keyCode: UInt16(kVK_ANSI_N),
            modifierFlags: [.command, .shift]
        )
        #expect(cmdShiftN != nil)
        #expect(cmdShiftN?.displayString == "⇧⌘N")

        let optCmdN = HotKeyCombo.from(
            keyCode: UInt16(kVK_ANSI_N),
            modifierFlags: [.option, .command]
        )
        #expect(optCmdN == .defaultToggle)

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

    @Test("Return after Int.max ordered-list marker falls back safely instead of overflowing")
    func orderedListOverflowSafe() {
        let maxText = "\(Int.max). item"
        let edit = MarkdownEditing.handleNewline(
            in: maxText,
            selection: NSRange(location: (maxText as NSString).length, length: 0)
        )
        #expect(edit == nil)

        let hugeText = "999999999999999999999999999. item"
        let hugeEdit = MarkdownEditing.handleNewline(
            in: hugeText,
            selection: NSRange(location: (hugeText as NSString).length, length: 0)
        )
        #expect(hugeEdit == nil)
    }

    @Test("Smart list continuation is suppressed inside fenced code blocks")
    func smartListSuppressedInCodeFence() {
        let fenced = "```bash\n- item"
        let edit = MarkdownEditing.handleNewline(
            in: fenced,
            selection: NSRange(location: (fenced as NSString).length, length: 0)
        )
        #expect(edit == nil)

        let afterFence = "```bash\n- inside\n```\n- outside"
        let outsideEdit = MarkdownEditing.handleNewline(
            in: afterFence,
            selection: NSRange(location: (afterFence as NSString).length, length: 0)
        )
        #expect(outsideEdit != nil)
        #expect(apply(outsideEdit!, to: afterFence) == afterFence + "\n- ")
    }

    @Test("Enter at column 0 or inside checkbox prefix pushes row down without splitting - [x]")
    func enterBeforeCheckboxNeverSplitsPrefix() {
        let task = "- [x] Ship release"
        // Column 0
        let atStart = MarkdownEditing.handleNewline(in: task, selection: NSRange(location: 0, length: 0))
        #expect(atStart != nil)
        #expect(apply(atStart!, to: task) == "\n- [x] Ship release")
        #expect(atStart?.newSelection == NSRange(location: 0, length: 0))

        // Inside prefix (between `-` and `[x]`)
        let midPrefix = MarkdownEditing.handleNewline(in: task, selection: NSRange(location: 2, length: 0))
        #expect(midPrefix != nil)
        #expect(apply(midPrefix!, to: task) == "\n- [x] Ship release")
    }

    @Test("Backspace atomically removes checklist prefix and horizontal rule lines")
    func atomicBackspaceOnCheckboxAndDivider() {
        let task = "- [x] Ship release"
        // Right after `- [x] ` (index 6)
        let delPrefix = MarkdownEditing.handleDeleteBackward(in: task, selection: NSRange(location: 6, length: 0))
        #expect(delPrefix != nil)
        #expect(apply(delPrefix!, to: task) == "Ship release")
        #expect(delPrefix?.newSelection == NSRange(location: 0, length: 0))

        // Inside `- [x]` (index 4)
        let delInside = MarkdownEditing.handleDeleteBackward(in: task, selection: NSRange(location: 4, length: 0))
        #expect(delInside != nil)
        #expect(apply(delInside!, to: task) == "Ship release")

        // Horizontal rule line `---`
        let divider = "Above\n---\nBelow"
        let delDivider = MarkdownEditing.handleDeleteBackward(in: divider, selection: NSRange(location: 9, length: 0))
        #expect(delDivider != nil)
        #expect(apply(delDivider!, to: divider) == "Above\n\nBelow")
    }

    @Test("Double hyphen + space expands into horizontal rule divider outside code fences")
    func doubleHyphenSpaceHorizontalRule() {
        let text = "Intro\n--"
        let edit = MarkdownEditing.handleSpace(in: text, selection: NSRange(location: (text as NSString).length, length: 0))
        #expect(edit != nil)
        #expect(apply(edit!, to: text) == "Intro\n---\n")

        // Must NOT trigger inside a fenced code block or mid-line
        let fenced = "```sql\n--"
        #expect(MarkdownEditing.handleSpace(in: fenced, selection: NSRange(location: (fenced as NSString).length, length: 0)) == nil)
        let midLine = "foo --"
        #expect(MarkdownEditing.handleSpace(in: midLine, selection: NSRange(location: (midLine as NSString).length, length: 0)) == nil)
    }

    @Test("Roman numeral lists continue, exit, protect col-0 Enter, and delete atomically on Backspace")
    func romanNumeralListsBehavior() {
        #expect(MarkdownEditing.parseCanonicalRoman("i")?.value == 1)
        #expect(MarkdownEditing.parseCanonicalRoman("iv")?.value == 4)
        #expect(MarkdownEditing.parseCanonicalRoman("IX")?.value == 9)
        #expect(MarkdownEditing.parseCanonicalRoman("IX")?.uppercase == true)
        #expect(MarkdownEditing.parseCanonicalRoman("iiii") == nil)
        #expect(MarkdownEditing.parseCanonicalRoman("Iv") == nil)

        let r1 = "i. first"
        let e1 = MarkdownEditing.handleNewline(in: r1, selection: NSRange(location: (r1 as NSString).length, length: 0))
        #expect(e1 != nil)
        #expect(apply(e1!, to: r1) == "i. first\nii. ")

        let r3 = "iii. third"
        let e3 = MarkdownEditing.handleNewline(in: r3, selection: NSRange(location: (r3 as NSString).length, length: 0))
        #expect(apply(e3!, to: r3) == "iii. third\niv. ")

        let rUpper = "III. Section"
        let eUpper = MarkdownEditing.handleNewline(in: rUpper, selection: NSRange(location: (rUpper as NSString).length, length: 0))
        #expect(apply(eUpper!, to: rUpper) == "III. Section\nIV. ")

        // Empty Roman item exits cleanly
        let emptyRoman = "ii. "
        let exitRoman = MarkdownEditing.handleNewline(in: emptyRoman, selection: NSRange(location: 4, length: 0))
        #expect(apply(exitRoman!, to: emptyRoman) == "")

        // Col-0 Enter pushes intact Roman item down
        let col0 = MarkdownEditing.handleNewline(in: r3, selection: NSRange(location: 0, length: 0))
        #expect(apply(col0!, to: r3) == "\niii. third")

        // Backspace after `iv. `, `- `, `1. ` removes the entire prefix atomically
        let romanDel = MarkdownEditing.handleDeleteBackward(in: "iv. fourth", selection: NSRange(location: 4, length: 0))
        #expect(apply(romanDel!, to: "iv. fourth") == "fourth")
        let bulletDel = MarkdownEditing.handleDeleteBackward(in: "- item", selection: NSRange(location: 2, length: 0))
        #expect(apply(bulletDel!, to: "- item") == "item")
        let numDel = MarkdownEditing.handleDeleteBackward(in: "12. dozen", selection: NSRange(location: 4, length: 0))
        #expect(apply(numDel!, to: "12. dozen") == "dozen")
    }

    @Test("toggleBulletList (⌘⇧8) and toggleNumberedList (⌘⇧9) toggle and convert single and multi-line blocks")
    func toggleBulletAndNumberedLists() {
        let plain = "alpha\nbeta"
        let toBullets = MarkdownEditing.toggleBulletList(in: plain, selection: NSRange(location: 0, length: (plain as NSString).length))
        let bulleted = apply(toBullets, to: plain)
        #expect(bulleted == "- alpha\n- beta")

        let backToPlain = MarkdownEditing.toggleBulletList(in: bulleted, selection: toBullets.newSelection)
        #expect(apply(backToPlain, to: bulleted) == plain)

        let toNumbers = MarkdownEditing.toggleNumberedList(in: bulleted, selection: NSRange(location: 0, length: (bulleted as NSString).length))
        let numbered = apply(toNumbers, to: bulleted)
        #expect(numbered == "1. alpha\n2. beta")

        let clearNumbers = MarkdownEditing.toggleNumberedList(in: numbered, selection: toNumbers.newSelection)
        #expect(apply(clearNumbers, to: numbered) == plain)

        // Single-line numbered toggle continues from previous numbered line
        let continued = "1. one\ntwo"
        let addNum = MarkdownEditing.toggleNumberedList(in: continued, selection: NSRange(location: 10, length: 0))
        #expect(apply(addNum, to: continued) == "1. one\n2. two")

        // List toggle skips fenced code blocks without corrupting delimiters or code lines
        let withFence = "before\n```swift\nlet x = 1\n```\nafter"
        let toggled = MarkdownEditing.toggleBulletList(in: withFence, selection: NSRange(location: 0, length: (withFence as NSString).length))
        #expect(apply(toggled, to: withFence) == "- before\n```swift\nlet x = 1\n```\n- after")
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

    @Test("Applies word-wrapping line break mode to base and list paragraphs")
    func wordWrapParagraphStyle() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "A very long paragraph\n- A very long checklist item"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let baseStyle = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let listIdx = (text as NSString).range(of: "- ").location
        let listStyle = storage.attribute(.paragraphStyle, at: listIdx, effectiveRange: nil) as? NSParagraphStyle

        #expect(baseStyle?.lineBreakMode == .byWordWrapping)
        #expect(listStyle?.lineBreakMode == .byWordWrapping)
    }

    @Test("Font and size updates invalidate styler caches and restyle cleanly")
    func stylerCacheInvalidation() {
        let styler = MarkdownStyler(baseFontSize: 14, fontFamily: "system")
        let storage = NSTextStorage(string: "# Heading\n- **Bold** *italic* `code`")
        styler.styleAll(storage)

        let h1Before = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(h1Before?.pointSize == 20)

        styler.baseFontSize = 18
        styler.fontFamily = "Menlo"
        styler.styleAll(storage)

        let h1After = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let bodyFont = styler.baseAttributes()[.font] as? NSFont
        #expect(h1After?.pointSize == 24)
        #expect(bodyFont?.familyName == "Menlo")
        #expect(bodyFont?.pointSize == 18)
    }

    @Test("Large Markdown document styles cleanly without quadratic slowdown")
    func largeDocumentStyling() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let block = "# Section\n- [ ] Check **bold** and *italic* with `code`\n> Quoted line\nPlain text line\n\n"
        let doc = String(repeating: block, count: 400)
        let storage = NSTextStorage(string: doc)
        styler.styleAll(storage)

        let firstHashColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(firstHashColor == .tertiaryLabelColor)

        let tailIdx = max(0, storage.length - 5)
        let tailFont = storage.attribute(.font, at: tailIdx, effectiveRange: nil) as? NSFont
        #expect(tailFont?.pointSize == 14)
    }

    @Test("Splitting a styled heading paragraph resets formatting on the moved suffix")
    func splitHeadingResetsSuffixStyling() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let storage = NSTextStorage(string: "# Heading")
        styler.styleAll(storage)

        // Simulate pressing Return between "Head" and "ing" -> "# Head\ning"
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "\n")
        styler.style(storage, in: NSRange(location: 6, length: 1))
        storage.endEditing()

        let headFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let suffixFont = storage.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect((headFont?.pointSize ?? 0) > 14)
        #expect(suffixFont?.pointSize == 14)
    }

    @Test("Fenced code blocks style body lines as code and suppress heading/inline rules")
    func fencedCodeBlockBodyStyling() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "```swift\n# Not a heading\n**not bold**\n```\n# Real Heading"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let nsText = text as NSString
        let insideHashIdx = nsText.range(of: "Not a heading").location
        let insideBoldIdx = nsText.range(of: "not bold").location
        let outsideHeadingIdx = nsText.range(of: "Real Heading").location

        let insideFont = storage.attribute(.font, at: insideHashIdx, effectiveRange: nil) as? NSFont
        let insideCodeAttr = storage.attribute(MarkdownStyler.codeBlockAttribute, at: insideHashIdx, effectiveRange: nil) as? Int
        let insideBoldFont = storage.attribute(.font, at: insideBoldIdx, effectiveRange: nil) as? NSFont
        let outsideFont = storage.attribute(.font, at: outsideHeadingIdx, effectiveRange: nil) as? NSFont
        let outsideCodeAttr = storage.attribute(MarkdownStyler.codeBlockAttribute, at: outsideHeadingIdx, effectiveRange: nil) as? Int

        #expect(insideCodeAttr == 1)
        #expect(insideFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect(insideBoldFont?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        #expect((outsideFont?.pointSize ?? 0) > 14)
        #expect(outsideCodeAttr == nil)

        // Deleting the opening fence restyles the former code body incrementally
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 9), with: "plain\n")
        styler.style(storage, in: NSRange(location: 0, length: 6))
        storage.endEditing()

        let updatedText = storage.string as NSString
        let promotedHeadingIdx = updatedText.range(of: "Not a heading").location
        let promotedFont = storage.attribute(.font, at: promotedHeadingIdx, effectiveRange: nil) as? NSFont
        #expect((promotedFont?.pointSize ?? 0) > 14)
    }

    @Test("Adjacent triple-backtick fences restyle cleanly on edit and get distinct code-block IDs")
    func adjacentFencesAndDistinctBlockIDs() {
        let styler = MarkdownStyler(baseFontSize: 14)

        // Two adjacent fenced blocks must receive distinct block IDs (1 and 2)
        let twoBlocks = "```\nfirst\n```\n```\nsecond\n```"
        let twoStorage = NSTextStorage(string: twoBlocks)
        styler.styleAll(twoStorage)
        let nsTwo = twoBlocks as NSString
        let id1 = twoStorage.attribute(MarkdownStyler.codeBlockAttribute, at: nsTwo.range(of: "first").location, effectiveRange: nil) as? Int
        let id2 = twoStorage.attribute(MarkdownStyler.codeBlockAttribute, at: nsTwo.range(of: "second").location, effectiveRange: nil) as? Int
        #expect(id1 == 1)
        #expect(id2 == 2)

        // Two consecutive ``` lines followed by `# heading`: deleting one backtick from line 1 opens fence 2
        let adjacent = "```\n```\n# Heading"
        let storage = NSTextStorage(string: adjacent)
        styler.styleAll(storage)
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 2, length: 1), with: "")
        styler.style(storage, in: NSRange(location: 2, length: 0))
        storage.endEditing()

        let updated = storage.string as NSString
        let headingIdx = updated.range(of: "Heading").location
        let codeID = storage.attribute(MarkdownStyler.codeBlockAttribute, at: headingIdx, effectiveRange: nil) as? Int
        let font = storage.attribute(.font, at: headingIdx, effectiveRange: nil) as? NSFont
        #expect(codeID != nil)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test("URLs with balanced parentheses and short local URLs receive full link destinations")
    func balancedParenAndShortURLs() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "See https://example.org/page_(topic) and [Wiki](https://example.org/page_(topic)) and http://x"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let nsText = text as NSString
        let bareIdx = nsText.range(of: "https://example.org/page_(topic)").location
        let mdIdx = nsText.range(of: "Wiki").location
        let shortIdx = nsText.range(of: "http://x").location

        #expect((storage.attribute(MarkdownStyler.linkURLAttribute, at: bareIdx, effectiveRange: nil) as? URL)?.absoluteString == "https://example.org/page_(topic)")
        #expect((storage.attribute(MarkdownStyler.linkURLAttribute, at: mdIdx, effectiveRange: nil) as? URL)?.absoluteString == "https://example.org/page_(topic)")
        #expect((storage.attribute(MarkdownStyler.linkURLAttribute, at: shortIdx, effectiveRange: nil) as? URL)?.absoluteString == "http://x")
    }

    @Test("Blockquotes, checkboxes, and Cmd-click links attach custom rendering attributes")
    func blockquoteCheckboxAndLinkAttributes() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "> Quote line\n- [ ] Open\n- [x] Done\nVisit [Notecast](https://notecast.app) or https://example.org/docs. and `https://ignored.dev`"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let nsText = text as NSString
        let quoteIdx = nsText.range(of: "Quote").location
        #expect(storage.attribute(MarkdownStyler.blockquoteAttribute, at: quoteIdx, effectiveRange: nil) as? Bool == true)

        let uncheckedBracketIdx = nsText.range(of: "[ ]").location
        let checkedBracketIdx = nsText.range(of: "[x]").location
        #expect(storage.attribute(MarkdownStyler.checkboxStateAttribute, at: uncheckedBracketIdx, effectiveRange: nil) as? Int == 0)
        #expect(storage.attribute(MarkdownStyler.checkboxStateAttribute, at: checkedBracketIdx, effectiveRange: nil) as? Int == 1)

        let mdLinkIdx = nsText.range(of: "Notecast").location
        let bareLinkIdx = nsText.range(of: "example.org").location
        let codeLinkIdx = nsText.range(of: "ignored.dev").location
        #expect((storage.attribute(MarkdownStyler.linkURLAttribute, at: mdLinkIdx, effectiveRange: nil) as? URL)?.absoluteString == "https://notecast.app")
        #expect((storage.attribute(MarkdownStyler.linkURLAttribute, at: bareLinkIdx, effectiveRange: nil) as? URL)?.absoluteString == "https://example.org/docs")
        #expect(storage.attribute(MarkdownStyler.linkURLAttribute, at: codeLinkIdx, effectiveRange: nil) == nil)
    }

    @Test("Horizontal rules attach divider attribute and checked/unchecked slots use identical fixed-width font")
    func horizontalRuleAndFixedWidthCheckboxSlot() {
        let styler = MarkdownStyler(baseFontSize: 14)
        let text = "- [ ] Open\n- [x] Done\n---\nNext"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let nsText = text as NSString
        let uncheckedFont = storage.attribute(.font, at: nsText.range(of: "- [ ]").location, effectiveRange: nil) as? NSFont
        let checkedFont = storage.attribute(.font, at: nsText.range(of: "- [x]").location, effectiveRange: nil) as? NSFont
        #expect(uncheckedFont != nil)
        #expect(uncheckedFont == checkedFont)
        #expect(uncheckedFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)

        let hrIdx = nsText.range(of: "---").location
        #expect(storage.attribute(MarkdownStyler.horizontalRuleAttribute, at: hrIdx, effectiveRange: nil) as? Bool == true)
    }

    @Test("Bullet, numbered, and Roman numeral lists attach expected marker attributes")
    func bulletNumberedAndRomanListStyling() {
        let styler = MarkdownStyler(baseFontSize: 14, accentColor: UIAccent.violet.nsColor)
        let text = "- Top bullet\n  - Nested bullet\n1. First\niv. Fourth"
        let storage = NSTextStorage(string: text)
        styler.styleAll(storage)

        let nsText = text as NSString
        let topDashIdx = nsText.range(of: "- Top").location
        let nestedDashIdx = nsText.range(of: "- Nested").location
        #expect(storage.attribute(MarkdownStyler.bulletMarkerAttribute, at: topDashIdx, effectiveRange: nil) as? Int == 0)
        #expect(storage.attribute(MarkdownStyler.bulletMarkerAttribute, at: nestedDashIdx, effectiveRange: nil) as? Int == 1)

        let numIdx = nsText.range(of: "1.").location
        let romanIdx = nsText.range(of: "iv.").location
        let numColor = storage.attribute(.foregroundColor, at: numIdx, effectiveRange: nil) as? NSColor
        let romanColor = storage.attribute(.foregroundColor, at: romanIdx, effectiveRange: nil) as? NSColor
        #expect(numColor != nil)
        #expect(romanColor != nil)
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

    @Test("Places settings window outside floating panel when space allows")
    func settingsOriginAvoidsPanel() {
        let settingsSize = NSSize(width: 490, height: 545)

        // Panel centered-left: Settings fits cleanly on the right
        let leftPanel = NSRect(x: 200, y: 200, width: 420, height: 520)
        let rightOrigin = WindowFrameClamper.settingsOrigin(for: settingsSize, avoiding: leftPanel, in: mainVisible)
        let rightRect = NSRect(origin: rightOrigin, size: settingsSize)
        #expect(mainVisible.contains(rightRect))
        #expect(!rightRect.intersects(leftPanel))
        #expect(rightRect.minX >= leftPanel.maxX)

        // Panel near right edge: Settings shifts to the left
        let rightPanel = NSRect(x: 1060, y: 200, width: 420, height: 520)
        let leftOrigin = WindowFrameClamper.settingsOrigin(for: settingsSize, avoiding: rightPanel, in: mainVisible)
        let leftRect = NSRect(origin: leftOrigin, size: settingsSize)
        #expect(mainVisible.contains(leftRect))
        #expect(!leftRect.intersects(rightPanel))
        #expect(leftRect.maxX <= rightPanel.minX)

        // Huge panel filling screen: falls back inside visibleFrame
        let fullPanel = NSRect(x: 50, y: 50, width: 1400, height: 850)
        let fallbackOrigin = WindowFrameClamper.settingsOrigin(for: settingsSize, avoiding: fullPanel, in: mainVisible)
        let fallbackRect = NSRect(origin: fallbackOrigin, size: settingsSize)
        #expect(mainVisible.contains(fallbackRect))
    }

    @Test("Keeps ghost wake zone accessible when dragged off-screen")
    func ensuresWakeZoneAccessible() {
        let onScreen = NSRect(x: 300, y: 200, width: 420, height: 520)
        let untouched = WindowFrameClamper.ensureWakeZoneAccessible(
            onScreen,
            wakeZoneFraction: 0.45,
            to: [mainVisible],
            fallbackVisibleFrame: mainVisible
        )
        #expect(untouched == onScreen)

        // Dragged off right edge so wake zone is unreachable -> snaps right edge safely inside screen
        let offRight = NSRect(x: 1380, y: 200, width: 420, height: 520)
        let adjustedRight = WindowFrameClamper.ensureWakeZoneAccessible(
            offRight,
            wakeZoneFraction: 0.45,
            to: [mainVisible],
            fallbackVisibleFrame: mainVisible,
            lastSafeFrame: onScreen
        )
        #expect(adjustedRight.maxX <= mainVisible.maxX)
        #expect(adjustedRight.maxX >= mainVisible.maxX - 16)

        // Dragged completely off all screens -> restores lastSafeFrame
        let completelyOff = NSRect(x: -1200, y: -1200, width: 420, height: 520)
        let restoredSafe = WindowFrameClamper.ensureWakeZoneAccessible(
            completelyOff,
            wakeZoneFraction: 0.45,
            to: [mainVisible],
            fallbackVisibleFrame: mainVisible,
            lastSafeFrame: onScreen
        )
        #expect(restoredSafe == onScreen)

        // Completely off without lastSafeFrame -> clamps into fallback visible frame
        let restoredFallback = WindowFrameClamper.ensureWakeZoneAccessible(
            completelyOff,
            wakeZoneFraction: 0.45,
            to: [mainVisible],
            fallbackVisibleFrame: mainVisible,
            lastSafeFrame: nil
        )
        #expect(mainVisible.contains(restoredFallback))
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

    @Test("Title extraction caps huge lines safely including emoji surrogate pairs")
    func titleExtractionCapsHugeLines() {
        let hugeLine = "# " + String(repeating: "🚀", count: 500) + " tail"
        let secondLine = String(repeating: "a", count: 2_000)
        let extracted = NoteLibraryStore.extractTitleAndPreview(from: "\(hugeLine)\n\(secondLine)")
        #expect(extracted.title.count <= 80)
        #expect(extracted.title.hasPrefix("🚀"))
        #expect(extracted.preview.count <= 100)
        #expect(extracted.preview.hasPrefix("aaaa"))
    }

    @Test("Debounced save defers index.json rewrite when title/preview unchanged and flushes on flushSync")
    func deferredIndexWriteAndFlush() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let indexURL = notesDir.appendingPathComponent("index.json")
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        let note = try store.createNote(initialContent: "# Title\nPreview line\nBody v1")
        let indexDataBefore = try Data(contentsOf: indexURL)
        // Compact JSON (no pretty-printing)
        #expect(!String(decoding: indexDataBefore, as: UTF8.self).contains("\n"))

        // Edit body only (title & preview unchanged): debounced save writes .md but skips index.json rewrite
        let updatedBody = "# Title\nPreview line\nBody v2"
        await withCheckedContinuation { continuation in
            store.scheduleSave(noteID: note.id, content: updatedBody, delay: 0.03) { _ in
                continuation.resume()
            }
        }

        let mdURL = notesDir.appendingPathComponent("\(note.id.uuidString).md")
        #expect(try String(contentsOf: mdURL, encoding: .utf8) == updatedBody)
        #expect(try Data(contentsOf: indexURL) == indexDataBefore)

        // flushSync writes the deferred index update cleanly
        try store.flushSync()
        let reloaded = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        #expect(reloaded.loadContent(for: note.id) == updatedBody)
    }

    @Test("Failed save preserves pending buffer and reports error without losing edits")
    func failedSavePreservesPendingBuffer() async throws {
        let dir = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        let note = try store.createNote(initialContent: "# Draft\nOriginal")

        // Make notes directory read-only to force write failure
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notesDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notesDir.path)
        }

        let unsavedText = "# Draft\nImportant unsaved edit"
        let gotError: Bool = await withCheckedContinuation { continuation in
            store.scheduleSave(
                noteID: note.id,
                content: unsavedText,
                delay: 0.03,
                onSaved: { _ in continuation.resume(returning: false) },
                onError: { _ in continuation.resume(returning: true) }
            )
        }
        #expect(gotError)
        // Pending buffer must still be preserved when loading the note
        #expect(store.loadContent(for: note.id) == unsavedText)

        // Restore permissions and verify flushSync persists the preserved buffer
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notesDir.path)
        try store.flushSync()
        let reloaded = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        #expect(reloaded.loadContent(for: note.id) == unsavedText)
    }

    @Test("Search session cache finds uncached notes and clears cleanly without evicting active note")
    func searchSessionCacheAndActivePinning() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        var createdIDs: [UUID] = []
        for idx in 0..<30 {
            let marker = idx == 0 ? "unique_needle_alpha" : "filler_\(idx)"
            let meta = try store.createNote(initialContent: "# Note \(idx)\nSummary \(idx)\n\(marker)")
            createdIDs.append(meta.id)
        }

        // Reload fresh store so none of the 30 bodies are cached yet
        let reloaded = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        let active = reloaded.lastOpenedNote()
        let activeUpdatedBefore = active.updatedAt

        let hits = reloaded.searchNotes(query: "unique_needle_alpha")
        #expect(hits.map(\.id) == [createdIDs[0]])
        reloaded.clearSearchCache()

        // Loading active note and flushing unchanged content must not bump updatedAt
        let activeContent = reloaded.loadContent(for: active.id)
        try reloaded.flushSync(noteID: active.id, content: activeContent)
        let activeAfter = reloaded.allNotes().first { $0.id == active.id }
        #expect(activeAfter?.updatedAt == activeUpdatedBefore)
    }

    @Test("Deleting an inactive note preserves the current active note and never overwrites a third note")
    func deleteInactiveNotePreservesActive() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        let noteA = try store.createNote(initialContent: "# Note A\nOlder active text")
        let noteB = try store.createNote(initialContent: "# Note B\nNewer untouched text")
        let noteC = try store.createNote(initialContent: "# Note C\nTo be deleted")

        // Make A the active note even though B is newer
        store.setLastOpenedNote(noteA.id)
        #expect(store.lastOpenedNote().id == noteA.id)

        // Delete inactive C: active note MUST remain A (not jump to B)
        let survivor = try store.deleteNote(id: noteC.id)
        #expect(survivor.id == noteA.id)
        #expect(store.lastOpenedNote().id == noteA.id)

        // Flushing A's text must leave B's on-disk file intact
        try store.flushSync(noteID: survivor.id, content: "# Note A\nOlder active text edited")
        let bURL = notesDir.appendingPathComponent("\(noteB.id.uuidString).md")
        #expect(try String(contentsOf: bURL, encoding: .utf8) == "# Note B\nNewer untouched text")
    }

    @Test("loadContentStrict throws on unreadable files and detects external edits on disk")
    func strictLoadAndExternalEditDetection() throws {
        let dir = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        let note = try store.createNote(initialContent: "# Original\nInitial body")
        let fileURL = notesDir.appendingPathComponent("\(note.id.uuidString).md")

        // Prime cache
        let initial = try store.loadContentStrict(for: note.id)
        #expect(initial.content == "# Original\nInitial body")
        #expect(!initial.hasPendingEdits)

        // Simulate external atomic edit on disk
        try Data("# External Edit\nUpdated outside app".utf8).write(to: fileURL, options: [.atomic])
        let refreshed = try store.loadContentStrict(for: note.id)
        #expect(refreshed.content == "# External Edit\nUpdated outside app")

        // On a fresh store (cache miss), an unreadable file must throw instead of silently returning ""
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }
        let freshStore = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        #expect(throws: (any Error).self) {
            _ = try freshStore.loadContentStrict(for: note.id)
        }
    }

    @Test("Manifest-only index.json write failure is reported and retried on flushSync")
    func manifestOnlyWriteFailureRetried() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let indexURL = notesDir.appendingPathComponent("index.json")
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        let note = try store.createNote(initialContent: "# Old Title\nBody")

        // Replace index.json with a non-empty directory so .md writes succeed while index.json atomic rename fails
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)
        try Data("blocker".utf8).write(to: indexURL.appendingPathComponent("lock"))

        let newText = "# New Title\nBody"
        let gotError: Bool = await withCheckedContinuation { continuation in
            store.scheduleSave(
                noteID: note.id,
                content: newText,
                delay: 0.03,
                onSaved: { _ in continuation.resume(returning: false) },
                onError: { _ in continuation.resume(returning: true) }
            )
        }
        #expect(gotError)
        #expect(store.hasPendingChanges())

        // Remove blocking directory and verify flushSync persists the updated index.json
        try FileManager.default.removeItem(at: indexURL)
        try store.flushSync()
        #expect(!store.hasPendingChanges())

        let reloaded = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)
        #expect(reloaded.allNotes().first(where: { $0.id == note.id })?.title == "New Title")
    }

    @Test("extractTitle stops after the first non-empty line")
    func extractTitleOnly() {
        let doc = "\n\n# **Quick** Title\n" + String(repeating: "\n", count: 5_000)
        #expect(NoteLibraryStore.extractTitle(from: doc) == "Quick Title")
        #expect(NoteLibraryStore.extractTitle(from: "   \n\n") == "Untitled Note")
    }

    @Test("Failed deleteNote rolls back the staged file and in-memory index intact")
    func failedDeleteRollsBack() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("notes", isDirectory: true)
        let indexURL = notesDir.appendingPathComponent("index.json")
        let store = NoteLibraryStore(directoryURL: notesDir, legacyScratchpadURL: nil, useStarterIfEmpty: false)

        let note1 = try store.createNote(initialContent: "# Keep Me\nOriginal body")
        let note2 = try store.createNote(initialContent: "# Delete Target\nMust rollback on failure")
        let targetURL = notesDir.appendingPathComponent("\(note2.id.uuidString).md")

        // Block index.json so deleteNote fails on manifest write
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)
        try Data("lock".utf8).write(to: indexURL.appendingPathComponent("lock"))

        #expect(throws: (any Error).self) {
            _ = try store.deleteNote(id: note2.id)
        }

        // File and index entry MUST both be rolled back intact
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "# Delete Target\nMust rollback on failure")
        #expect(store.allNotes().map(\.id).contains(note2.id))
        #expect(store.allNotes().map(\.id).contains(note1.id))
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

    @Test("Notes-only mode returns only notes even for empty or command-prefix queries")
    func notesOnlyMode() {
        let emptyEntries = CommandPaletteSearch.results(query: "", matchingNotes: sampleNotes, mode: .notesOnly)
        #expect(emptyEntries.count == sampleNotes.count)
        #expect(emptyEntries.allSatisfy {
            if case .note = $0 { return true }
            return false
        })

        let prefixEntries = CommandPaletteSearch.results(query: ">neon", matchingNotes: [sampleNotes[1]], mode: .notesOnly)
        #expect(prefixEntries == [.note(sampleNotes[1])])
    }

    @Test("Ghost outline command matches >ghost query")
    func ghostCommandSearch() {
        let entries = CommandPaletteSearch.results(query: ">ghost", matchingNotes: sampleNotes)
        #expect(entries.contains {
            if case .command(let cmd) = $0 { return cmd.id == .toggleGhostMode }
            return false
        })
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
        #expect(settings.surfaceStyle == .charcoal)
        #expect(settings.neonGlowEnabled == true)
        #expect(settings.neonAccent == .cyan)
        #expect(settings.uiAccent == .cyan)
        #expect(settings.checkboxStyle == .circle)
        #expect(settings.fontFamily == "system")
        #expect(settings.ghostOnUnfocus == false)
        #expect(settings.ghostWakeZoneFraction == AppSettings.defaultGhostWakeZoneFraction)
        #expect(settings.hasSeenOnboardingGuide == false)

        settings.surfaceStyle = .midnightSlate
        settings.neonGlowEnabled = false
        settings.neonAccent = .magenta
        settings.uiAccent = .violet
        settings.checkboxStyle = .square
        settings.fontFamily = "system-serif"
        settings.ghostOnUnfocus = true
        settings.ghostWakeZoneFraction = 0.30
        settings.hasSeenOnboardingGuide = true

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.surfaceStyle == .midnightSlate)
        #expect(reloaded.neonGlowEnabled == false)
        #expect(reloaded.neonAccent == .magenta)
        #expect(reloaded.uiAccent == .violet)
        #expect(reloaded.checkboxStyle == .square)
        #expect(reloaded.fontFamily == "system-serif")
        #expect(reloaded.ghostOnUnfocus == true)
        #expect(reloaded.hasSeenOnboardingGuide == true)
        #expect(abs(reloaded.ghostWakeZoneFraction - 0.30) < 0.0001)

        reloaded.ghostWakeZoneFraction = 0.02
        #expect(reloaded.ghostWakeZoneFraction == AppSettings.minGhostWakeZoneFraction)
        reloaded.ghostWakeZoneFraction = 1.5
        #expect(reloaded.ghostWakeZoneFraction == AppSettings.maxGhostWakeZoneFraction)
        #expect(SurfaceStyle.allCases.count == 12)
        #expect(SurfaceStyle.warmPaper.isLight)
        #expect(SurfaceStyle.coolMist.isLight)
        #expect(SurfaceStyle.graphite.isOpaque)
        #expect(SurfaceStyle.charcoal.isOpaque)
        #expect(!SurfaceStyle.translucentHUD.isOpaque)
    }

    @Test("MarkdownStyler.resolveFont resolves system, rounded, serif, mono, Menlo, and unknown fallback")
    func fontResolution() {
        let sys = MarkdownStyler.resolveFont(family: "system", size: 15)
        #expect(sys.pointSize == 15)

        let rounded = MarkdownStyler.resolveFont(family: "system-rounded", size: 15)
        #expect(rounded.pointSize == 15)

        let serif = MarkdownStyler.resolveFont(family: "system-serif", size: 15)
        #expect(serif.pointSize == 15)

        let mono = MarkdownStyler.resolveFont(family: "system-mono", size: 13)
        #expect(mono.fontDescriptor.symbolicTraits.contains(.monoSpace))

        let menlo = MarkdownStyler.resolveFont(family: "Menlo", size: 16)
        #expect(menlo.familyName == "Menlo")
        #expect(menlo.pointSize == 16)

        let fallback = MarkdownStyler.resolveFont(family: "DefinitelyNonExistentFontXYZ_123", size: 14)
        #expect(fallback.pointSize == 14)
    }

    @Test("NotecastBrandIcon renders valid lossless PNG and menu/header icons")
    func brandIconRendering() {
        let pngData = NotecastBrandIcon.renderPNGData(pixelSize: 64)
        #expect(pngData != nil)
        if let bytes = pngData {
            #expect(Array(bytes.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        }

        let menuImage = NotecastBrandIcon.menuBarImage()
        #expect(menuImage.size == NSSize(width: 18, height: 18))
        #expect(menuImage.isTemplate == true)

        let headerImage = NotecastBrandIcon.headerIconImage(accentColor: NeonAccent.violet.nsColor, isActive: true)
        #expect(headerImage.size == NSSize(width: 18, height: 18))
        #expect(headerImage.isTemplate == false)
    }

    @Test("Deleting large selections including end-of-note does not throw or stale selection")
    @MainActor
    func deleteLargeSelectionRegression() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 380, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let styler = MarkdownStyler()

        final class HarnessTextView: NSTextView, @MainActor NSTextStorageDelegate {
            let styler: MarkdownStyler
            var isStyling = false
            var pendingEditedRange: NSRange?
            var changeCallbackCount = 0

            init(frame: NSRect, container: NSTextContainer, styler: MarkdownStyler) {
                self.styler = styler
                super.init(frame: frame, textContainer: container)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            func textStorage(
                _ textStorage: NSTextStorage,
                didProcessEditing editedMask: NSTextStorageEditActions,
                range editedRange: NSRange,
                changeInLength delta: Int
            ) {
                guard editedMask.contains(.editedCharacters), !isStyling else { return }
                if let existing = pendingEditedRange {
                    pendingEditedRange = NSUnionRange(existing, editedRange)
                } else {
                    pendingEditedRange = editedRange
                }
            }

            override func didChangeText() {
                super.didChangeText()
                guard !isStyling else { return }

                let rangeToStyle = pendingEditedRange ?? selectedRange()
                pendingEditedRange = nil

                if let storage = textStorage {
                    isStyling = true
                    storage.beginEditing()
                    styler.style(storage, in: rangeToStyle)
                    storage.endEditing()
                    isStyling = false
                }

                typingAttributes = styler.baseAttributes()
                changeCallbackCount += 1
            }
        }

        let textView = HarnessTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 400), container: container, styler: styler)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        storage.delegate = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView

        let originalText = "# Heading One\n\n- [ ] Task **bold** item\n- [x] Done `code`\nAnother paragraph with *italic* words\n"
        textView.isStyling = true
        textView.string = originalText
        styler.styleAll(storage)
        textView.typingAttributes = styler.baseAttributes()
        textView.undoManager?.removeAllActions()
        textView.isStyling = false
        layoutManager.ensureLayout(for: container)

        // Delete middle selection across multiple Markdown paragraphs
        textView.setSelectedRange(NSRange(location: 5, length: 50))
        textView.deleteBackward(nil)
        #expect(textView.selectedRange().location == 5)
        #expect(textView.selectedRange().length == 0)

        // Delete selection extending to the very end of text (previously threw NSRangeException)
        let tailStart = 8
        textView.setSelectedRange(NSRange(location: tailStart, length: storage.length - tailStart))
        textView.deleteBackward(nil)
        #expect(storage.length == tailStart)
        #expect(textView.selectedRange() == NSRange(location: tailStart, length: 0))

        // Select all and delete, then verify undo & subsequent typing work cleanly
        textView.selectAll(nil)
        textView.deleteBackward(nil)
        #expect(storage.length == 0)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

        textView.undoManager?.undo()
        #expect(textView.string == originalText)

        textView.insertText(" + next", replacementRange: NSRange(location: storage.length, length: 0))
        #expect(textView.string.hasSuffix(" + next"))
        #expect(textView.changeCallbackCount >= 5)
    }
}
