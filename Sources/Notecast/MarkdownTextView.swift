import AppKit
import Carbon.HIToolbox
import NotecastCore

/// Distraction-free `NSTextView` with live paragraph-scoped Markdown styling and smart list editing.
@MainActor
final class MarkdownTextView: NSTextView, @MainActor NSTextStorageDelegate {
    var onTextChanged: ((String) -> Void)?
    var onFontSizeDelta: ((CGFloat) -> Void)?
    var onFontSizeReset: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenSearch: (() -> Void)?
    var onOpenNotesSearch: (() -> Void)?
    var onNewNote: (() -> Void)?
    var onToggleNotesList: (() -> Void)?

    private let styler: MarkdownStyler
    private var isApplyingStyling = false
    private var pendingEditedRange: NSRange?

    private static let listLinePrefixRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[-*+]|\d+\.)\s"#
    )

    init(
        frame frameRect: NSRect,
        textContainer container: NSTextContainer?,
        fontSize: CGFloat,
        fontFamily: String,
        accentColor: NSColor
    ) {
        self.styler = MarkdownStyler(
            baseFontSize: fontSize,
            fontFamily: fontFamily,
            accentColor: accentColor
        )
        super.init(frame: frameRect, textContainer: container)
        configureEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureEditor() {
        // Keep `isRichText = true` so `NSTextStorage` retains per-range Markdown attributes,
        // while forcing plain-text paste and disabling graphics imports.
        isRichText = true
        importsGraphics = false
        allowsUndo = true
        isEditable = true
        isSelectable = true
        usesFindPanel = true
        isIncrementalSearchingEnabled = true

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false

        drawsBackground = false
        insertionPointColor = styler.accentColor
        (layoutManager as? MarkdownLayoutManager)?.accentColor = styler.accentColor
        textContainerInset = NSSize(width: 16, height: 12)

        font = MarkdownStyler.resolveFont(family: styler.fontFamily, size: styler.baseFontSize)
        textColor = .labelColor
        typingAttributes = styler.baseAttributes()

        textStorage?.delegate = self
    }

    func loadInitialText(_ text: String) {
        isApplyingStyling = true
        pendingEditedRange = nil
        string = text
        if let storage = textStorage {
            styler.styleAll(storage)
        }
        typingAttributes = styler.baseAttributes()
        undoManager?.removeAllActions()
        isApplyingStyling = false
    }

    func applyFont(family: String, size: CGFloat) {
        styler.fontFamily = family
        styler.baseFontSize = size
        restyleAll()
    }

    func applyAccentColor(_ color: NSColor) {
        styler.accentColor = color
        insertionPointColor = color
        (layoutManager as? MarkdownLayoutManager)?.accentColor = color
        restyleAll()
        needsDisplay = true
    }

    private func restyleAll() {
        if let storage = textStorage {
            isApplyingStyling = true
            styler.styleAll(storage)
            isApplyingStyling = false
        }
        typingAttributes = styler.baseAttributes()
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters), !isApplyingStyling else { return }

        if let existing = pendingEditedRange {
            pendingEditedRange = NSUnionRange(existing, editedRange)
        } else {
            pendingEditedRange = editedRange
        }
    }

    override func didChangeText() {
        super.didChangeText()
        guard !isApplyingStyling else { return }

        // Defer restyling while IME marked text is active so `setAttributes` does not wipe
        // composition underlines; `pendingEditedRange` stays queued until composition commits.
        if hasMarkedText() {
            onTextChanged?(string)
            return
        }

        let rangeToStyle = pendingEditedRange ?? selectedRange()
        pendingEditedRange = nil

        if let storage = textStorage {
            isApplyingStyling = true
            storage.beginEditing()
            styler.style(storage, in: rangeToStyle)
            storage.endEditing()
            isApplyingStyling = false
        }

        typingAttributes = styler.baseAttributes()
        onTextChanged?(string)
    }

    // MARK: - Plain-Text Paste

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    // MARK: - Smart Editing & Checklist Clicks

    override func insertNewline(_ sender: Any?) {
        if let result = MarkdownEditing.handleNewline(in: string, selection: selectedRange()) {
            applyEditResult(result)
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length > 0 || isCursorOnListLine(selection) {
            if let result = MarkdownEditing.adjustIndentation(in: string, selection: selection, outdent: false) {
                applyEditResult(result, actionName: "Indent")
                return
            }
        }
        if shouldChangeText(in: selection, replacementString: "  ") {
            textStorage?.replaceCharacters(in: selection, with: "  ")
            let maxLen = textStorage?.length ?? 0
            setSelectedRange(NSRange(location: min(selection.location + 2, maxLen), length: 0))
            didChangeText()
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let result = MarkdownEditing.adjustIndentation(in: string, selection: selectedRange(), outdent: true) {
            applyEditResult(result, actionName: "Outdent")
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1,
           let layoutManager,
           let textContainer
        {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: viewPoint.x - textContainerOrigin.x,
                y: viewPoint.y - textContainerOrigin.y
            )
            var fraction: CGFloat = 0
            let charIndex = layoutManager.characterIndex(
                for: containerPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            let hitRect = glyphRect.insetBy(dx: -4, dy: -2)
            if hitRect.contains(containerPoint) {
                if event.modifierFlags.contains(.command),
                   let storage = textStorage,
                   charIndex < storage.length,
                   let url = storage.attribute(MarkdownStyler.linkURLAttribute, at: charIndex, effectiveRange: nil) as? URL
                {
                    NSWorkspace.shared.open(url)
                    return
                }
                if let result = MarkdownEditing.toggleCheckboxAtCharacterIndex(charIndex, in: string) {
                    applyEditResult(result, actionName: "Toggle Task")
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers == [.command] {
            switch key {
            case "c":
                copy(nil)
                return true
            case "v":
                pasteAsPlainText(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "z":
                undoManager?.undo()
                return true
            case "b":
                applyEditResult(
                    MarkdownEditing.toggleWrapper(in: string, selection: selectedRange(), marker: "**"),
                    actionName: "Bold"
                )
                return true
            case "i":
                applyEditResult(
                    MarkdownEditing.toggleWrapper(in: string, selection: selectedRange(), marker: "*"),
                    actionName: "Italic"
                )
                return true
            case "e":
                applyEditResult(
                    MarkdownEditing.toggleWrapper(in: string, selection: selectedRange(), marker: "`"),
                    actionName: "Inline Code"
                )
                return true
            case "=", "+":
                onFontSizeDelta?(1)
                return true
            case "-":
                onFontSizeDelta?(-1)
                return true
            case "0":
                onFontSizeReset?()
                return true
            case ",":
                onOpenSettings?()
                return true
            case "p":
                onOpenSearch?()
                return true
            case "n":
                onNewNote?()
                return true
            case "l":
                onToggleNotesList?()
                return true
            default:
                if Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter {
                    applyEditResult(
                        MarkdownEditing.toggleChecklist(in: string, selection: selectedRange()),
                        actionName: "Toggle Checklist"
                    )
                    return true
                }
            }
        } else if modifiers == [.command, .shift] {
            switch key {
            case "p":
                onOpenNotesSearch?()
                return true
            case "z":
                undoManager?.redo()
                return true
            case "x":
                applyEditResult(
                    MarkdownEditing.toggleWrapper(in: string, selection: selectedRange(), marker: "~~"),
                    actionName: "Strikethrough"
                )
                return true
            case "l":
                applyEditResult(
                    MarkdownEditing.toggleChecklist(in: string, selection: selectedRange()),
                    actionName: "Toggle Checklist"
                )
                return true
            case "=", "+":
                onFontSizeDelta?(1)
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Helpers

    private func isCursorOnListLine(_ selection: NSRange) -> Bool {
        let nsText = string as NSString
        guard selection.location <= nsText.length else { return false }
        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        return Self.listLinePrefixRegex.firstMatch(in: string, range: lineRange) != nil
    }

    private func applyEditResult(_ result: MarkdownEditing.EditResult, actionName: String? = nil) {
        guard shouldChangeText(in: result.replacementRange, replacementString: result.replacementText) else {
            return
        }
        textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacementText)
        let maxLen = textStorage?.length ?? 0
        let clampedLoc = min(max(0, result.newSelection.location), maxLen)
        let clampedLen = min(max(0, result.newSelection.length), maxLen - clampedLoc)
        setSelectedRange(NSRange(location: clampedLoc, length: clampedLen))
        didChangeText()
        if let actionName {
            undoManager?.setActionName(actionName)
        }
    }
}
