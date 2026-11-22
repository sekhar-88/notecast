import AppKit
import Foundation

/// Incremental, paragraph-scoped Markdown styler for `NSTextStorage`.
public final class MarkdownStyler {
    public static let codeBlockAttribute = NSAttributedString.Key("NotecastCodeBlock")
    public static let blockquoteAttribute = NSAttributedString.Key("NotecastBlockquote")
    public static let checkboxStateAttribute = NSAttributedString.Key("NotecastCheckboxState")
    public static let bulletMarkerAttribute = NSAttributedString.Key("NotecastBulletMarker")
    public static let horizontalRuleAttribute = NSAttributedString.Key("NotecastHorizontalRule")
    public static let linkURLAttribute = NSAttributedString.Key("NotecastLinkURL")

    public static let curatedFontFamilies: [(id: String, label: String)] = [
        ("system", "System (SF Pro)"),
        ("system-rounded", "SF Pro Rounded"),
        ("system-serif", "New York (Serif)"),
        ("system-mono", "SF Mono"),
        ("Avenir Next", "Avenir Next"),
        ("Menlo", "Menlo"),
        ("Georgia", "Georgia"),
        ("Helvetica Neue", "Helvetica Neue")
    ]

    private struct TraitFontKey: Hashable {
        let fontName: String
        let pointSizeBits: UInt
        let traitRaw: UInt
    }

    public var baseFontSize: CGFloat {
        didSet {
            if baseFontSize != oldValue {
                invalidateStyleCaches()
            }
        }
    }

    public var fontFamily: String {
        didSet {
            if fontFamily != oldValue {
                invalidateStyleCaches()
            }
        }
    }

    public var accentColor: NSColor

    private let baseParagraphStyle: NSParagraphStyle
    private let codeBlockParagraphStyle: NSParagraphStyle
    private var cachedBaseFont: NSFont?
    private var cachedMonoFont: NSFont?
    private var cachedCheckboxSlotFont: NSFont?
    private var cachedBulletSlotFont: NSFont?
    private var cachedNumberMarkerFont: NSFont?
    private var cachedHeadingFonts: [Int: NSFont] = [:]
    private var cachedTraitFonts: [TraitFontKey: NSFont] = [:]
    private var cachedHangingIndentStyles: [Int: NSParagraphStyle] = [:]
    private var cachedBlockquoteIndentStyles: [Int: NSParagraphStyle] = [:]
    private var cachedPrefixWidths: [String: CGFloat] = [:]

    private let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,4})\s+(.+)$"#)
    private let blockquoteRegex = try! NSRegularExpression(pattern: #"^(\s*>\s?)(.*)$"#)
    private let fenceRegex = try! NSRegularExpression(pattern: #"^\s*```.*$"#)
    private let horizontalRuleRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:---+|\*\*\*+|___+)[ \t]*$"#)
    private let checklistRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]\s+\[([ xX])\])(?:\s+(.*))?$"#)
    private let bulletListRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+])\s+(.*)$"#)
    private let numberedListRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(\d+\.)\s+(.*)$"#)
    private let romanListRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(([ivxlcdmIVXLCDM]+)\.)\s+(.*)$"#)

    private let inlineCodeRegex = try! NSRegularExpression(pattern: #"(`[^`\n]+`)"#)
    private let markdownLinkRegex = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\((https?://(?:[^\s()\n]+|\([^\s()\n]*\))+)\)"#)
    private let bareURLRegex = try! NSRegularExpression(pattern: #"(?<![(\w])(https?://[^\s<>\[\]`"'\n]+)"#)
    private let boldItalicRegex = try! NSRegularExpression(pattern: #"(\*\*\*[^*\n]+\*\*\*)"#)
    private let boldRegex = try! NSRegularExpression(pattern: #"(?<!\*)(\*\*[^*\n]+\*\*)(?!\*)|(?<!_)(__[^_\n]+__)(?!_)"#)
    private let italicRegex = try! NSRegularExpression(
        pattern: #"(?<![*\w])(\*[^*\s](?:[^*\n]*?[^*\s])?\*|(?<!_)_[^_\s](?:[^_\n]*?[^_\s])?_(?!_))(?![*\w])"#
    )
    private let strikethroughRegex = try! NSRegularExpression(pattern: #"(~~[^~\n]+~~)"#)

    public init(
        baseFontSize: CGFloat = 14,
        fontFamily: String = "system",
        accentColor: NSColor = .controlAccentColor
    ) {
        self.baseFontSize = baseFontSize
        self.fontFamily = fontFamily
        self.accentColor = accentColor

        let mutableBase = NSMutableParagraphStyle()
        mutableBase.lineSpacing = 3.5
        mutableBase.lineBreakMode = .byWordWrapping
        self.baseParagraphStyle = mutableBase.copy() as! NSParagraphStyle

        let mutableCode = NSMutableParagraphStyle()
        mutableCode.lineSpacing = 3.0
        mutableCode.firstLineHeadIndent = 10
        mutableCode.headIndent = 10
        mutableCode.tailIndent = -10
        mutableCode.lineBreakMode = .byWordWrapping
        self.codeBlockParagraphStyle = mutableCode.copy() as! NSParagraphStyle
    }

    /// Returns `true` if `location` falls inside an open triple-backtick fenced code block.
    public static func isInsideFencedCodeBlock(before location: Int, in nsString: NSString) -> Bool {
        fencedCodeState(before: location, in: nsString).inFence
    }

    private static func fencedCodeState(before location: Int, in nsString: NSString) -> (inFence: Bool, openedBlockCount: Int) {
        let limit = min(max(0, location), nsString.length)
        guard limit >= 3 else { return (false, 0) }

        var inFence = false
        var openedBlocks = 0
        var searchLoc = 0
        while searchLoc < limit {
            let hit = nsString.range(
                of: "```",
                options: [],
                range: NSRange(location: searchLoc, length: limit - searchLoc)
            )
            if hit.location == NSNotFound {
                break
            }

            var cursor = hit.location
            var onlyLeadingWhitespace = true
            while cursor > 0 {
                let prev = nsString.character(at: cursor - 1)
                if prev == 10 || prev == 13 {
                    break
                }
                if prev != 32 && prev != 9 {
                    onlyLeadingWhitespace = false
                    break
                }
                cursor -= 1
            }

            if onlyLeadingWhitespace {
                if !inFence {
                    openedBlocks += 1
                }
                inFence.toggle()
                let lineRange = nsString.lineRange(for: NSRange(location: hit.location, length: 0))
                searchLoc = min(limit, NSMaxRange(lineRange))
            } else {
                searchLoc = NSMaxRange(hit)
            }
        }
        return (inFence, openedBlocks)
    }

    private func invalidateStyleCaches() {
        cachedBaseFont = nil
        cachedMonoFont = nil
        cachedCheckboxSlotFont = nil
        cachedBulletSlotFont = nil
        cachedNumberMarkerFont = nil
        cachedHeadingFonts.removeAll(keepingCapacity: true)
        cachedTraitFonts.removeAll(keepingCapacity: true)
        cachedPrefixWidths.removeAll(keepingCapacity: true)
    }

    private func resolvedCheckboxSlotFont() -> NSFont {
        if let cachedCheckboxSlotFont {
            return cachedCheckboxSlotFont
        }
        let font = NSFont.monospacedSystemFont(ofSize: max(6.0, baseFontSize * 0.48), weight: .regular)
        cachedCheckboxSlotFont = font
        return font
    }

    private func resolvedBulletSlotFont() -> NSFont {
        if let cachedBulletSlotFont {
            return cachedBulletSlotFont
        }
        let font = NSFont.monospacedSystemFont(ofSize: max(10.0, baseFontSize * 0.90), weight: .regular)
        cachedBulletSlotFont = font
        return font
    }

    private func resolvedNumberMarkerFont() -> NSFont {
        if let cachedNumberMarkerFont {
            return cachedNumberMarkerFont
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: baseFontSize, weight: .medium)
        cachedNumberMarkerFont = font
        return font
    }

    private func resolvedBaseFont() -> NSFont {
        if let cachedBaseFont {
            return cachedBaseFont
        }
        let font = Self.resolveFont(family: fontFamily, size: baseFontSize)
        cachedBaseFont = font
        return font
    }

    private func resolvedMonoFont() -> NSFont {
        if let cachedMonoFont {
            return cachedMonoFont
        }
        let font = NSFont.monospacedSystemFont(ofSize: max(10, baseFontSize - 1), weight: .regular)
        cachedMonoFont = font
        return font
    }

    private func resolvedHeadingFont(level: Int) -> NSFont {
        if let cached = cachedHeadingFonts[level] {
            return cached
        }
        let delta: CGFloat = switch level {
        case 1: 6
        case 2: 4
        case 3: 2
        default: 1
        }
        let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
        let font = Self.resolveFont(family: fontFamily, size: baseFontSize + delta, weight: weight)
        cachedHeadingFonts[level] = font
        return font
    }

    private func measuredPrefixWidth(_ prefix: String, font: NSFont) -> CGFloat {
        if let cached = cachedPrefixWidths[prefix] {
            return cached
        }
        let width = (prefix as NSString).size(withAttributes: [.font: font]).width
        if cachedPrefixWidths.count >= 256 {
            cachedPrefixWidths.removeAll(keepingCapacity: true)
        }
        cachedPrefixWidths[prefix] = width
        return width
    }

    public static func resolveFont(
        family: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        switch family {
        case "system":
            return NSFont.systemFont(ofSize: size, weight: weight)
        case "system-rounded":
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: size)
            {
                return font
            }
            return base
        case "system-serif":
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.serif),
               let font = NSFont(descriptor: descriptor, size: size)
            {
                return font
            }
            return base
        case "system-mono":
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        default:
            let isBold = weight == .bold || weight == .semibold || weight == .heavy
            let traits: NSFontTraitMask = isBold ? .boldFontMask : []
            let weightValue = (weight == .bold || weight == .heavy) ? 9 : (weight == .semibold ? 7 : 5)

            if let resolved = NSFontManager.shared.font(
                withFamily: family,
                traits: traits,
                weight: weightValue,
                size: size
            ) {
                return resolved
            }

            var descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            if isBold {
                descriptor = descriptor.withSymbolicTraits(.bold)
            }
            if let fromDescriptor = NSFont(descriptor: descriptor, size: size),
               fromDescriptor.familyName == family || !fromDescriptor.fontName.isEmpty
            {
                // Verify NSFontDescriptor actually matched a real installed family rather than silently failing
                if fromDescriptor.familyName?.caseInsensitiveCompare(family) == .orderedSame {
                    return fromDescriptor
                }
            }

            return NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    public func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: resolvedBaseFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraphStyle
        ]
    }

    /// Styles the full document wrapped in a single `beginEditing`/`endEditing` transaction.
    public func styleAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        style(storage, in: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    /// Incrementally styles the paragraph(s) intersecting `targetRange`.
    public func style(_ storage: NSTextStorage, in targetRange: NSRange) {
        let totalLength = storage.length
        guard totalLength > 0 else { return }

        let clampedLoc = min(max(0, targetRange.location), totalLength)
        let clampedLen = min(max(0, targetRange.length), totalLength - clampedLoc)
        let clampedRange = NSRange(location: clampedLoc, length: clampedLen)

        let text = storage.string
        let nsString = text as NSString
        var paragraphRange = nsString.paragraphRange(for: clampedRange)
        guard paragraphRange.length > 0 else { return }

        // If an edit inserted or ended on the trailing newline of `paragraphRange` (e.g. splitting
        // `# Heading` with Return), include the immediately following paragraph so the moved suffix
        // does not keep stale heading/list styling.
        let paragraphEnd = NSMaxRange(paragraphRange)
        if paragraphEnd < totalLength, NSMaxRange(clampedRange) == paragraphEnd {
            let lastChar = nsString.character(at: paragraphEnd - 1)
            if lastChar == 10 || lastChar == 13 {
                let nextParagraph = nsString.paragraphRange(for: NSRange(location: paragraphEnd, length: 0))
                paragraphRange = NSUnionRange(paragraphRange, nextParagraph)
            }
        }

        let defaults = baseAttributes()
        let baseFont = resolvedBaseFont()

        let entryState = Self.fencedCodeState(before: paragraphRange.location, in: nsString)
        var inFence = entryState.inFence
        var activeCodeBlockID = entryState.openedBlockCount
        let startEnd = NSMaxRange(paragraphRange)

        // Check whether any part of `paragraphRange` previously carried a code-block attribute
        // (catches deleting/editing a fence delimiter even beside another adjacent fence).
        var hadCodeInParagraph = false
        storage.enumerateAttribute(Self.codeBlockAttribute, in: paragraphRange, options: []) { value, _, stop in
            if value != nil {
                hadCodeInParagraph = true
                stop.pointee = true
            }
        }

        var styleRange = paragraphRange
        var sawFenceDelimiter = false
        var scanFence = inFence
        var scanIndex = paragraphRange.location
        while scanIndex < startEnd {
            let fullLineRange = nsString.lineRange(for: NSRange(location: scanIndex, length: 0))
            let contentRange = trimmedLineRange(fullLineRange, in: nsString)
            if contentRange.length > 0, fenceRegex.firstMatch(in: text, range: contentRange) != nil {
                sawFenceDelimiter = true
                scanFence.toggle()
            }
            let nextIndex = NSMaxRange(fullLineRange)
            guard nextIndex > scanIndex else { break }
            scanIndex = nextIndex
        }

        if startEnd < totalLength {
            let tailWasCodeBlock = storage.attribute(Self.codeBlockAttribute, at: startEnd, effectiveRange: nil) != nil
            if sawFenceDelimiter || hadCodeInParagraph || (scanFence != tailWasCodeBlock) {
                styleRange = NSRange(location: paragraphRange.location, length: totalLength - paragraphRange.location)
            }
        }

        storage.setAttributes(defaults, range: styleRange)

        var nonInlineLineRanges: [NSRange] = []
        var index = styleRange.location
        let end = NSMaxRange(styleRange)
        while index < end {
            let fullLineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let contentRange = trimmedLineRange(fullLineRange, in: nsString)
            let isFenceDelimiter = contentRange.length > 0
                && fenceRegex.firstMatch(in: text, range: contentRange) != nil

            if isFenceDelimiter {
                if !inFence {
                    activeCodeBlockID += 1
                    inFence = true
                } else {
                    inFence = false
                }
                let mono = resolvedMonoFont()
                storage.addAttributes(
                    [
                        .font: mono,
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: codeBlockParagraphStyle,
                        Self.codeBlockAttribute: activeCodeBlockID
                    ],
                    range: fullLineRange
                )
                if contentRange.length > 0 {
                    nonInlineLineRanges.append(contentRange)
                }
            } else if inFence {
                let mono = resolvedMonoFont()
                storage.addAttributes(
                    [
                        .font: mono,
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: codeBlockParagraphStyle,
                        Self.codeBlockAttribute: activeCodeBlockID
                    ],
                    range: fullLineRange
                )
                if contentRange.length > 0 {
                    nonInlineLineRanges.append(contentRange)
                }
            } else if contentRange.length > 0 {
                let skipInline = styleLine(
                    storage,
                    text: text,
                    nsString: nsString,
                    fullLineRange: fullLineRange,
                    lineRange: contentRange,
                    baseFont: baseFont
                )
                if skipInline {
                    nonInlineLineRanges.append(contentRange)
                }
            }

            let nextIndex = NSMaxRange(fullLineRange)
            guard nextIndex > index else { break }
            index = nextIndex
        }

        styleInlineElements(storage, text: text, nsString: nsString, in: styleRange, skipping: nonInlineLineRanges)
    }

    // MARK: - Line-Level Rules

    @discardableResult
    private func styleLine(
        _ storage: NSTextStorage,
        text: String,
        nsString: NSString,
        fullLineRange: NSRange,
        lineRange: NSRange,
        baseFont: NSFont
    ) -> Bool {
        if horizontalRuleRegex.firstMatch(in: text, range: lineRange) != nil {
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    Self.horizontalRuleAttribute: true
                ],
                range: lineRange
            )
            return true
        }

        if let match = headingRegex.firstMatch(in: text, range: lineRange) {
            let hashesRange = match.range(at: 1)
            let level = hashesRange.length
            let headingFont = resolvedHeadingFont(level: level)

            storage.addAttribute(.font, value: headingFont, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: hashesRange)
            return false
        }

        if let match = blockquoteRegex.firstMatch(in: text, range: lineRange) {
            let markerRange = match.range(at: 1)
            let bodyRange = match.range(at: 2)

            storage.addAttribute(Self.blockquoteAttribute, value: true, range: fullLineRange)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.tertiaryLabelColor.withAlphaComponent(0.55),
                range: markerRange
            )
            if bodyRange.length > 0 {
                let italicQuoteFont = font(baseFont, withTrait: .italicFontMask)
                storage.addAttributes(
                    [
                        .font: italicQuoteFont,
                        .foregroundColor: NSColor.secondaryLabelColor
                    ],
                    range: bodyRange
                )
            }
            let prefixWidth = measuredPrefixWidth(nsString.substring(with: markerRange), font: baseFont)
            applyBlockquoteIndent(max(24, 12 + prefixWidth), to: storage, range: fullLineRange)
            return false
        }

        if let match = checklistRegex.firstMatch(in: text, range: lineRange) {
            let indentRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            let stateRange = match.range(at: 3)
            let bodyRange = match.range(at: 4)

            let stateChar = nsString.substring(with: stateRange)
            let isChecked = (stateChar == "x" || stateChar == "X")

            // Use a compact fixed-width monospace slot for the entire `- [ ]` / `- [x]` prefix so
            // checked and unchecked states have identical pixel width (zero horizontal jitter on toggle)
            // while MarkdownLayoutManager draws a crisp circular/rounded checkbox cleanly inside the slot.
            let slotFont = resolvedCheckboxSlotFont()
            storage.addAttributes(
                [
                    .font: slotFont,
                    .foregroundColor: NSColor.clear,
                    Self.checkboxStateAttribute: isChecked ? 1 : 0
                ],
                range: markerRange
            )

            // Give comfortable breathing room between the drawn checkbox and the task text.
            let spaceLoc = NSMaxRange(markerRange)
            let extraKern: CGFloat = 3.0
            if spaceLoc < NSMaxRange(lineRange) {
                storage.addAttribute(
                    .kern,
                    value: extraKern,
                    range: NSRange(location: spaceLoc, length: 1)
                )
            }

            let indentWidth = indentRange.length > 0
                ? measuredPrefixWidth(nsString.substring(with: indentRange), font: baseFont)
                : 0
            let markerWidth = measuredPrefixWidth("- [ ]", font: slotFont)
            let spaceWidth = measuredPrefixWidth(" ", font: baseFont) + extraKern
            applyHangingIndent(max(22, indentWidth + markerWidth + spaceWidth), to: storage, range: lineRange)

            if isChecked, bodyRange.location != NSNotFound, bodyRange.length > 0 {
                storage.addAttributes(
                    [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.secondaryLabelColor
                    ],
                    range: bodyRange
                )
            }
            return false
        }

        if let match = bulletListRegex.firstMatch(in: text, range: lineRange) {
            let indentRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            let slotFont = resolvedBulletSlotFont()
            let depth = indentRange.length > 0 ? 1 : 0

            storage.addAttributes(
                [
                    .font: slotFont,
                    .foregroundColor: NSColor.clear,
                    Self.bulletMarkerAttribute: depth
                ],
                range: markerRange
            )

            let spaceLoc = NSMaxRange(markerRange)
            let extraKern: CGFloat = 3.5
            if spaceLoc < NSMaxRange(lineRange) {
                storage.addAttribute(.kern, value: extraKern, range: NSRange(location: spaceLoc, length: 1))
            }

            let indentWidth = indentRange.length > 0
                ? measuredPrefixWidth(nsString.substring(with: indentRange), font: baseFont)
                : 0
            let markerWidth = measuredPrefixWidth("-", font: slotFont)
            let spaceWidth = measuredPrefixWidth(" ", font: baseFont) + extraKern
            applyHangingIndent(max(16, indentWidth + markerWidth + spaceWidth), to: storage, range: lineRange)
            return false
        }

        if let match = numberedListRegex.firstMatch(in: text, range: lineRange) {
            let indentRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            let numFont = resolvedNumberMarkerFont()

            storage.addAttributes(
                [
                    .font: numFont,
                    .foregroundColor: accentColor.withAlphaComponent(0.92)
                ],
                range: markerRange
            )

            let spaceLoc = NSMaxRange(markerRange)
            let extraKern: CGFloat = 2.5
            if spaceLoc < NSMaxRange(lineRange) {
                storage.addAttribute(.kern, value: extraKern, range: NSRange(location: spaceLoc, length: 1))
            }

            let indentWidth = indentRange.length > 0
                ? measuredPrefixWidth(nsString.substring(with: indentRange), font: baseFont)
                : 0
            let markerWidth = measuredPrefixWidth(nsString.substring(with: markerRange), font: numFont)
            let spaceWidth = measuredPrefixWidth(" ", font: baseFont) + extraKern
            applyHangingIndent(max(20, indentWidth + markerWidth + spaceWidth), to: storage, range: lineRange)
            return false
        }

        if let match = romanListRegex.firstMatch(in: text, range: lineRange) {
            let tokenRange = match.range(at: 3)
            let token = nsString.substring(with: tokenRange)
            if MarkdownEditing.parseCanonicalRoman(token) != nil {
                let indentRange = match.range(at: 1)
                let markerRange = match.range(at: 2)
                let markerFont = resolvedNumberMarkerFont()

                storage.addAttributes(
                    [
                        .font: markerFont,
                        .foregroundColor: accentColor.withAlphaComponent(0.92)
                    ],
                    range: markerRange
                )

                let spaceLoc = NSMaxRange(markerRange)
                let extraKern: CGFloat = 2.5
                if spaceLoc < NSMaxRange(lineRange) {
                    storage.addAttribute(.kern, value: extraKern, range: NSRange(location: spaceLoc, length: 1))
                }

                let indentWidth = indentRange.length > 0
                    ? measuredPrefixWidth(nsString.substring(with: indentRange), font: baseFont)
                    : 0
                let markerWidth = measuredPrefixWidth(nsString.substring(with: markerRange), font: markerFont)
                let spaceWidth = measuredPrefixWidth(" ", font: baseFont) + extraKern
                applyHangingIndent(max(20, indentWidth + markerWidth + spaceWidth), to: storage, range: lineRange)
                return false
            }
        }

        return false
    }

    // MARK: - Inline Rules

    private func styleInlineElements(
        _ storage: NSTextStorage,
        text: String,
        nsString: NSString,
        in range: NSRange,
        skipping skippedLineRanges: [NSRange]
    ) {
        var codeRanges: [NSRange] = []

        // 1. Inline code
        for match in inlineCodeRegex.matches(in: text, range: range) {
            let fullRange = match.range(at: 1)
            guard !overlapsAny(fullRange, in: skippedLineRanges), fullRange.length >= 2 else { continue }
            codeRanges.append(fullRange)

            let monoFont = resolvedMonoFont()
            storage.addAttributes(
                [
                    .font: monoFont,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ],
                range: fullRange
            )
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 1)
        }

        let protectedRanges = (skippedLineRanges + codeRanges).sorted { $0.location < $1.location }

        // 2. Markdown links `[label](https://...)` and bare URLs (Cmd-click to open)
        var linkRanges: [NSRange] = []
        for match in markdownLinkRegex.matches(in: text, range: range) {
            let fullRange = match.range
            let labelRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            guard !overlapsAny(fullRange, in: protectedRanges) else { continue }
            let urlString = nsString.substring(with: urlRange)
            guard let url = URL(string: urlString) else { continue }

            linkRanges.append(fullRange)
            storage.addAttribute(Self.linkURLAttribute, value: url, range: fullRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: fullRange)
            storage.addAttributes(
                [
                    .foregroundColor: accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: labelRange
            )
        }

        let urlExcludedRanges = (protectedRanges + linkRanges).sorted { $0.location < $1.location }
        for match in bareURLRegex.matches(in: text, range: range) {
            var urlRange = match.range(at: 1)
            guard !overlapsAny(urlRange, in: urlExcludedRanges) else { continue }

            // Trim trailing sentence punctuation and any unbalanced closing parentheses
            // while keeping balanced parentheses such as `https://example.org/page_(topic)`.
            while urlRange.length > 0 {
                let last = nsString.character(at: NSMaxRange(urlRange) - 1)
                if last == 46 || last == 44 || last == 59 || last == 58 || last == 33 || last == 63 {
                    urlRange.length -= 1
                } else if last == 41 { // ')'
                    var opens = 0
                    var closes = 0
                    for offset in 0..<urlRange.length {
                        let ch = nsString.character(at: urlRange.location + offset)
                        if ch == 40 { opens += 1 }
                        else if ch == 41 { closes += 1 }
                    }
                    if closes > opens {
                        urlRange.length -= 1
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            let urlString = nsString.substring(with: urlRange)
            guard let url = URL(string: urlString),
                  let host = url.host,
                  !host.isEmpty
            else { continue }

            storage.addAttributes(
                [
                    .foregroundColor: accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    Self.linkURLAttribute: url
                ],
                range: urlRange
            )
        }

        // 3. Bold + Italic (***text***)
        for match in boldItalicRegex.matches(in: text, range: range) {
            let fullRange = match.range(at: 1)
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 6 else { continue }
            applyTrait(.boldFontMask, to: storage, range: fullRange)
            applyTrait(.italicFontMask, to: storage, range: fullRange)
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 3)
        }

        // 4. Bold (**text** or __text__)
        for match in boldRegex.matches(in: text, range: range) {
            let fullRange = match.range
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 4 else { continue }
            applyTrait(.boldFontMask, to: storage, range: fullRange)
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 2)
        }

        // 5. Italic (*text* or _text_)
        for match in italicRegex.matches(in: text, range: range) {
            let fullRange = match.range(at: 1)
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 2 else { continue }
            applyTrait(.italicFontMask, to: storage, range: fullRange)
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 1)
        }

        // 6. Strikethrough (~~text~~)
        for match in strikethroughRegex.matches(in: text, range: range) {
            let fullRange = match.range(at: 1)
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 4 else { continue }
            let innerRange = NSRange(location: fullRange.location + 2, length: fullRange.length - 4)
            storage.addAttributes(
                [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                range: innerRange
            )
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 2)
        }
    }

    // MARK: - Attribute Helpers

    private func applyBlockquoteIndent(_ headIndent: CGFloat, to storage: NSTextStorage, range: NSRange) {
        let bucket = Int((headIndent * 2).rounded())
        let style: NSParagraphStyle
        if let cached = cachedBlockquoteIndentStyles[bucket] {
            style = cached
        } else {
            let mutable = NSMutableParagraphStyle()
            mutable.lineSpacing = 3.5
            mutable.lineBreakMode = .byWordWrapping
            mutable.firstLineHeadIndent = 12
            mutable.headIndent = CGFloat(bucket) / 2.0
            let immutable = mutable.copy() as! NSParagraphStyle
            if cachedBlockquoteIndentStyles.count >= 128 {
                cachedBlockquoteIndentStyles.removeAll(keepingCapacity: true)
            }
            cachedBlockquoteIndentStyles[bucket] = immutable
            style = immutable
        }
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func applyHangingIndent(_ indent: CGFloat, to storage: NSTextStorage, range: NSRange) {
        let bucket = Int((indent * 2).rounded())
        let style: NSParagraphStyle
        if let cached = cachedHangingIndentStyles[bucket] {
            style = cached
        } else {
            let mutable = NSMutableParagraphStyle()
            mutable.lineSpacing = 3.5
            mutable.lineBreakMode = .byWordWrapping
            mutable.headIndent = CGFloat(bucket) / 2.0
            let immutable = mutable.copy() as! NSParagraphStyle
            if cachedHangingIndentStyles.count >= 128 {
                cachedHangingIndentStyles.removeAll(keepingCapacity: true)
            }
            cachedHangingIndentStyles[bucket] = immutable
            style = immutable
        }
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func dimMarkers(in storage: NSTextStorage, fullRange: NSRange, markerLength: Int) {
        guard fullRange.length >= markerLength * 2 else { return }
        let openRange = NSRange(location: fullRange.location, length: markerLength)
        let closeRange = NSRange(location: NSMaxRange(fullRange) - markerLength, length: markerLength)
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openRange)
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeRange)
    }

    private func applyTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        let fallbackFont = resolvedBaseFont()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let current = (value as? NSFont) ?? fallbackFont
            let updated = font(current, withTrait: trait)
            storage.addAttribute(.font, value: updated, range: subRange)
        }
    }

    private func font(_ source: NSFont, withTrait trait: NSFontTraitMask) -> NSFont {
        let key = TraitFontKey(
            fontName: source.fontName,
            pointSizeBits: UInt(source.pointSize.bitPattern),
            traitRaw: trait.rawValue
        )
        if let cached = cachedTraitFonts[key] {
            return cached
        }

        let converted = NSFontManager.shared.convert(source, toHaveTrait: trait)
        let wantedSymbolic: NSFontDescriptor.SymbolicTraits = switch trait {
        case .boldFontMask: .bold
        case .italicFontMask: .italic
        default: []
        }

        let resolved: NSFont
        if !wantedSymbolic.isEmpty && !converted.fontDescriptor.symbolicTraits.contains(wantedSymbolic) {
            let combined = source.fontDescriptor.symbolicTraits.union(wantedSymbolic)
            let descriptor = source.fontDescriptor.withSymbolicTraits(combined)
            resolved = NSFont(descriptor: descriptor, size: source.pointSize) ?? converted
        } else {
            resolved = converted
        }

        if cachedTraitFonts.count >= 64 {
            cachedTraitFonts.removeAll(keepingCapacity: true)
        }
        cachedTraitFonts[key] = resolved
        return resolved
    }

    private func trimmedLineRange(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let ch = nsString.character(at: lineRange.location + length - 1)
            if ch == 10 || ch == 13 {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: lineRange.location, length: length)
    }

    private func overlapsAny(_ candidate: NSRange, in sortedDisjointRanges: [NSRange]) -> Bool {
        guard !sortedDisjointRanges.isEmpty, candidate.length > 0 else { return false }
        let candidateStart = candidate.location
        let candidateEnd = NSMaxRange(candidate)

        var low = 0
        var high = sortedDisjointRanges.count
        while low < high {
            let mid = low + (high - low) / 2
            if NSMaxRange(sortedDisjointRanges[mid]) <= candidateStart {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low < sortedDisjointRanges.count && sortedDisjointRanges[low].location < candidateEnd
    }
}
