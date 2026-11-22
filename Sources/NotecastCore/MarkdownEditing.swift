import Foundation

/// Pure UTF-16 `NSRange`-based Markdown editing transformations for `NSTextView`.
public enum MarkdownEditing {
    public struct EditResult: Equatable, Sendable {
        public let replacementRange: NSRange
        public let replacementText: String
        public let newSelection: NSRange

        public init(replacementRange: NSRange, replacementText: String, newSelection: NSRange) {
            self.replacementRange = replacementRange
            self.replacementText = replacementText
            self.newSelection = newSelection
        }
    }

    private static let checklistRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]) \[([ xX])\] (.*)$"#
    )
    private static let checklistToggleRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]) \[([ xX])\](?: (.*))?$"#
    )
    private static let checklistBracketRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*[-*+]\s+)(\[([ xX])\])(?:\s|$)"#
    )
    private static let unorderedListRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]) (.*)$"#
    )
    private static let orderedListRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(\d+)\. (.*)$"#
    )
    private static let leadingWhitespaceRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(.*)$"#
    )

    /// Continues or exits lists/checklists on Enter when the cursor is collapsed.
    public static func handleNewline(in text: String, selection: NSRange) -> EditResult? {
        guard selection.length == 0 else { return nil }

        let nsText = text as NSString
        guard selection.location <= nsText.length else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        if MarkdownStyler.isInsideFencedCodeBlock(before: lineRange.location, in: nsText) {
            return nil
        }
        let lineContentEnd = contentEnd(ofLineRange: lineRange, in: nsText)
        let prefixRange = NSRange(location: lineRange.location, length: selection.location - lineRange.location)
        let prefix = nsText.substring(with: prefixRange)
        let restIsEmpty = selection.location >= lineContentEnd

        if let match = firstMatch(checklistRegex, in: prefix) {
            let indent = capture(1, in: prefix, match: match)
            let bullet = capture(2, in: prefix, match: match)
            let itemText = capture(4, in: prefix, match: match)

            if itemText.isEmpty && restIsEmpty {
                return EditResult(
                    replacementRange: prefixRange,
                    replacementText: "",
                    newSelection: NSRange(location: lineRange.location, length: 0)
                )
            }
            let insertion = "\n\(indent)\(bullet) [ ] "
            return EditResult(
                replacementRange: selection,
                replacementText: insertion,
                newSelection: NSRange(location: selection.location + (insertion as NSString).length, length: 0)
            )
        }

        if let match = firstMatch(unorderedListRegex, in: prefix) {
            let indent = capture(1, in: prefix, match: match)
            let bullet = capture(2, in: prefix, match: match)
            let itemText = capture(3, in: prefix, match: match)

            if itemText.isEmpty && restIsEmpty {
                return EditResult(
                    replacementRange: prefixRange,
                    replacementText: "",
                    newSelection: NSRange(location: lineRange.location, length: 0)
                )
            }
            let insertion = "\n\(indent)\(bullet) "
            return EditResult(
                replacementRange: selection,
                replacementText: insertion,
                newSelection: NSRange(location: selection.location + (insertion as NSString).length, length: 0)
            )
        }

        if let match = firstMatch(orderedListRegex, in: prefix) {
            let indent = capture(1, in: prefix, match: match)
            let numberStr = capture(2, in: prefix, match: match)
            let itemText = capture(3, in: prefix, match: match)

            if itemText.isEmpty && restIsEmpty {
                return EditResult(
                    replacementRange: prefixRange,
                    replacementText: "",
                    newSelection: NSRange(location: lineRange.location, length: 0)
                )
            }
            guard let currentNumber = Int(numberStr) else {
                return nil
            }
            let (nextNumber, overflow) = currentNumber.addingReportingOverflow(1)
            guard !overflow else {
                return nil
            }
            let insertion = "\n\(indent)\(nextNumber). "
            return EditResult(
                replacementRange: selection,
                replacementText: insertion,
                newSelection: NSRange(location: selection.location + (insertion as NSString).length, length: 0)
            )
        }

        return nil
    }

    /// Wraps or unwraps the selection with an inline Markdown marker (`**`, `*`, `` ` ``, `~~`).
    public static func toggleWrapper(in text: String, selection: NSRange, marker: String) -> EditResult {
        let nsText = text as NSString
        let safeLoc = min(max(0, selection.location), nsText.length)
        let safeLen = min(max(0, selection.length), nsText.length - safeLoc)
        let clamped = NSRange(location: safeLoc, length: safeLen)
        let mLen = (marker as NSString).length

        if clamped.length >= 2 * mLen {
            let selected = nsText.substring(with: clamped)
            let shouldUnwrapInner: Bool
            if marker == "*" {
                // Avoid stripping a single `*` out of `**bold**`; unwrap `*text*` or `***text***`.
                let startsDoubleOnly = selected.hasPrefix("**") && !selected.hasPrefix("***")
                let endsDoubleOnly = selected.hasSuffix("**") && !selected.hasSuffix("***")
                shouldUnwrapInner = selected.hasPrefix("*") && selected.hasSuffix("*") && !(startsDoubleOnly && endsDoubleOnly)
            } else {
                shouldUnwrapInner = selected.hasPrefix(marker) && selected.hasSuffix(marker)
            }

            if shouldUnwrapInner {
                let innerRange = NSRange(location: clamped.location + mLen, length: clamped.length - 2 * mLen)
                let inner = nsText.substring(with: innerRange)
                return EditResult(
                    replacementRange: clamped,
                    replacementText: inner,
                    newSelection: NSRange(location: clamped.location, length: innerRange.length)
                )
            }
        }

        if clamped.location >= mLen, NSMaxRange(clamped) + mLen <= nsText.length {
            let beforeRange = NSRange(location: clamped.location - mLen, length: mLen)
            let afterRange = NSRange(location: NSMaxRange(clamped), length: mLen)
            let hasSurrounding: Bool
            if marker == "*" {
                let leftStars = countStars(in: nsText, endingAt: clamped.location)
                let rightStars = countStars(in: nsText, startingAt: NSMaxRange(clamped))
                hasSurrounding = (leftStars == 1 && rightStars == 1) || (leftStars >= 3 && rightStars >= 3)
            } else {
                hasSurrounding = nsText.substring(with: beforeRange) == marker && nsText.substring(with: afterRange) == marker
            }

            if hasSurrounding {
                let outerRange = NSRange(location: clamped.location - mLen, length: clamped.length + 2 * mLen)
                let inner = nsText.substring(with: clamped)
                return EditResult(
                    replacementRange: outerRange,
                    replacementText: inner,
                    newSelection: NSRange(location: clamped.location - mLen, length: clamped.length)
                )
            }
        }

        if clamped.length == 0 {
            return EditResult(
                replacementRange: clamped,
                replacementText: marker + marker,
                newSelection: NSRange(location: clamped.location + mLen, length: 0)
            )
        }

        let selected = nsText.substring(with: clamped)
        return EditResult(
            replacementRange: clamped,
            replacementText: marker + selected + marker,
            newSelection: NSRange(location: clamped.location + mLen, length: clamped.length)
        )
    }

    /// Toggles checklist state on the current line (`plain` → `- [ ] ` → `- [x] ` → `- [ ] `, or `- item` → `- [ ] item`).
    public static func toggleChecklist(in text: String, selection: NSRange) -> EditResult {
        let nsText = text as NSString
        let safeLoc = min(max(0, selection.location), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
        let lineContentEnd = contentEnd(ofLineRange: lineRange, in: nsText)
        let contentRange = NSRange(location: lineRange.location, length: lineContentEnd - lineRange.location)
        let lineContent = nsText.substring(with: contentRange)

        let replacement: String
        if let match = firstMatch(checklistToggleRegex, in: lineContent) {
            let indent = capture(1, in: lineContent, match: match)
            let bullet = capture(2, in: lineContent, match: match)
            let state = capture(3, in: lineContent, match: match)
            let rest = match.range(at: 4).location != NSNotFound ? capture(4, in: lineContent, match: match) : ""
            let nextState = (state == " ") ? "x" : " "
            replacement = "\(indent)\(bullet) [\(nextState)] \(rest)"
        } else if let match = firstMatch(unorderedListRegex, in: lineContent) {
            let indent = capture(1, in: lineContent, match: match)
            let bullet = capture(2, in: lineContent, match: match)
            let rest = capture(3, in: lineContent, match: match)
            replacement = "\(indent)\(bullet) [ ] \(rest)"
        } else if let match = firstMatch(leadingWhitespaceRegex, in: lineContent) {
            let indent = capture(1, in: lineContent, match: match)
            let rest = capture(2, in: lineContent, match: match)
            replacement = "\(indent)- [ ] \(rest)"
        } else {
            replacement = "- [ ] \(lineContent)"
        }

        let newLen = (replacement as NSString).length
        let delta = newLen - contentRange.length
        let newLoc = min(max(contentRange.location, safeLoc + delta), contentRange.location + newLen)

        return EditResult(
            replacementRange: contentRange,
            replacementText: replacement,
            newSelection: NSRange(location: newLoc, length: 0)
        )
    }

    /// Toggles `[ ]` ↔ `[x]` when `index` falls inside a checklist's 3-character bracket span.
    public static func toggleCheckboxAtCharacterIndex(_ index: Int, in text: String) -> EditResult? {
        let nsText = text as NSString
        guard index >= 0, index < nsText.length else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
        let lineContentEnd = contentEnd(ofLineRange: lineRange, in: nsText)
        let contentRange = NSRange(location: lineRange.location, length: lineContentEnd - lineRange.location)
        let lineContent = nsText.substring(with: contentRange)

        guard let match = firstMatch(checklistBracketRegex, in: lineContent) else {
            return nil
        }

        let localBracketRange = match.range(at: 2)
        let globalBracketRange = NSRange(
            location: contentRange.location + localBracketRange.location,
            length: localBracketRange.length
        )

        guard index >= globalBracketRange.location, index < NSMaxRange(globalBracketRange) else {
            return nil
        }

        let state = capture(3, in: lineContent, match: match)
        let flipped = (state == " ") ? "[x]" : "[ ]"
        return EditResult(
            replacementRange: globalBracketRange,
            replacementText: flipped,
            newSelection: NSRange(location: NSMaxRange(globalBracketRange), length: 0)
        )
    }

    /// Indents (`"  "`) or outdents (removes up to 2 spaces or 1 tab) all lines overlapping `selection`.
    public static func adjustIndentation(in text: String, selection: NSRange, outdent: Bool) -> EditResult? {
        let nsText = text as NSString
        let safeLoc = min(max(0, selection.location), nsText.length)
        let safeLen = min(max(0, selection.length), nsText.length - safeLoc)
        var effectiveRange = NSRange(location: safeLoc, length: safeLen)

        if effectiveRange.length > 0, nsText.character(at: NSMaxRange(effectiveRange) - 1) == 10 {
            effectiveRange.length -= 1
        }

        let blockRange = nsText.lineRange(for: effectiveRange)
        let blockEnd = contentEnd(ofLineRange: blockRange, in: nsText)
        let replaceRange = NSRange(location: blockRange.location, length: blockEnd - blockRange.location)
        let blockText = nsText.substring(with: replaceRange)

        let lines = blockText.components(separatedBy: "\n")
        var updatedLines: [String] = []
        updatedLines.reserveCapacity(lines.count)

        var firstDelta = 0
        var totalDelta = 0
        var changed = false

        for (idx, line) in lines.enumerated() {
            let newLine: String
            let delta: Int

            if outdent {
                if line.hasPrefix("\t") {
                    newLine = String(line.dropFirst())
                    delta = -1
                    changed = true
                } else if line.hasPrefix("  ") {
                    newLine = String(line.dropFirst(2))
                    delta = -2
                    changed = true
                } else if line.hasPrefix(" ") {
                    newLine = String(line.dropFirst())
                    delta = -1
                    changed = true
                } else {
                    newLine = line
                    delta = 0
                }
            } else {
                if lines.count == 1 || !line.isEmpty {
                    newLine = "  " + line
                    delta = 2
                    changed = true
                } else {
                    newLine = line
                    delta = 0
                }
            }

            if idx == 0 {
                firstDelta = delta
            }
            totalDelta += delta
            updatedLines.append(newLine)
        }

        guard changed else { return nil }

        let replacementText = updatedLines.joined(separator: "\n")
        let replacementLen = (replacementText as NSString).length

        let newLoc: Int
        let newLen: Int
        if safeLen == 0 {
            newLoc = min(max(replaceRange.location, safeLoc + firstDelta), replaceRange.location + replacementLen)
            newLen = 0
        } else {
            let startShift = (safeLoc > replaceRange.location) ? firstDelta : 0
            newLoc = min(max(replaceRange.location, safeLoc + startShift), replaceRange.location + replacementLen)
            let maxPossibleLen = (replaceRange.location + replacementLen) - newLoc
            newLen = min(max(0, safeLen + totalDelta - startShift), maxPossibleLen)
        }

        return EditResult(
            replacementRange: replaceRange,
            replacementText: replacementText,
            newSelection: NSRange(location: newLoc, length: newLen)
        )
    }

    // MARK: - Helpers

    private static func contentEnd(ofLineRange lineRange: NSRange, in text: NSString) -> Int {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location {
            let ch = text.character(at: end - 1)
            if ch == 10 || ch == 13 {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func firstMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: (string as NSString).length)
        return regex.firstMatch(in: string, range: range)
    }

    private static func capture(_ index: Int, in string: String, match: NSTextCheckingResult) -> String {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return (string as NSString).substring(with: range)
    }

    private static func countStars(in text: NSString, endingAt location: Int) -> Int {
        var count = 0
        var idx = location - 1
        while idx >= 0, text.character(at: idx) == 42 { // '*'
            count += 1
            idx -= 1
        }
        return count
    }

    private static func countStars(in text: NSString, startingAt location: Int) -> Int {
        var count = 0
        var idx = location
        while idx < text.length, text.character(at: idx) == 42 { // '*'
            count += 1
            idx += 1
        }
        return count
    }
}
