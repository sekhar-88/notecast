import AppKit
import Foundation

/// Incremental, paragraph-scoped Markdown styler for `NSTextStorage`.
public final class MarkdownStyler {
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
    private var cachedBaseFont: NSFont?
    private var cachedMonoFont: NSFont?
    private var cachedHeadingFonts: [Int: NSFont] = [:]
    private var cachedTraitFonts: [TraitFontKey: NSFont] = [:]
    private var cachedHangingIndentStyles: [Int: NSParagraphStyle] = [:]
    private var cachedPrefixWidths: [String: CGFloat] = [:]

    private let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,4})\s+(.+)$"#)
    private let blockquoteRegex = try! NSRegularExpression(pattern: #"^(\s*>\s?)(.*)$"#)
    private let fenceRegex = try! NSRegularExpression(pattern: #"^\s*```.*$"#)
    private let checklistRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]\s+\[([ xX])\])(?:\s+(.*))?$"#)
    private let listRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d+\.)\s+(.*)$"#)

    private let inlineCodeRegex = try! NSRegularExpression(pattern: #"(`[^`\n]+`)"#)
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
    }

    private func invalidateStyleCaches() {
        cachedBaseFont = nil
        cachedMonoFont = nil
        cachedHeadingFonts.removeAll(keepingCapacity: true)
        cachedTraitFonts.removeAll(keepingCapacity: true)
        cachedPrefixWidths.removeAll(keepingCapacity: true)
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
        let paragraphRange = nsString.paragraphRange(for: clampedRange)
        guard paragraphRange.length > 0 else { return }

        let defaults = baseAttributes()
        storage.setAttributes(defaults, range: paragraphRange)

        let baseFont = resolvedBaseFont()
        var nonInlineLineRanges: [NSRange] = []

        var index = paragraphRange.location
        let end = NSMaxRange(paragraphRange)
        while index < end {
            let fullLineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let contentRange = trimmedLineRange(fullLineRange, in: nsString)
            if contentRange.length > 0 {
                let isFence = styleLine(
                    storage,
                    text: text,
                    nsString: nsString,
                    lineRange: contentRange,
                    baseFont: baseFont
                )
                if isFence {
                    nonInlineLineRanges.append(contentRange)
                }
            }
            let nextIndex = NSMaxRange(fullLineRange)
            guard nextIndex > index else { break }
            index = nextIndex
        }

        styleInlineElements(storage, text: text, in: paragraphRange, skipping: nonInlineLineRanges)
    }

    // MARK: - Line-Level Rules

    @discardableResult
    private func styleLine(
        _ storage: NSTextStorage,
        text: String,
        nsString: NSString,
        lineRange: NSRange,
        baseFont: NSFont
    ) -> Bool {
        if fenceRegex.firstMatch(in: text, range: lineRange) != nil {
            let mono = resolvedMonoFont()
            storage.addAttributes(
                [
                    .font: mono,
                    .foregroundColor: NSColor.tertiaryLabelColor
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

            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: markerRange)
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
            applyHangingIndent(max(14, prefixWidth), to: storage, range: lineRange)
            return false
        }

        if let match = checklistRegex.firstMatch(in: text, range: lineRange) {
            let indentRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            let stateRange = match.range(at: 3)
            let bodyRange = match.range(at: 4)

            storage.addAttribute(.foregroundColor, value: accentColor, range: markerRange)

            let prefixEnd = NSMaxRange(markerRange)
            let prefixPlusSpaceLen = min(NSMaxRange(lineRange) - lineRange.location, (prefixEnd - lineRange.location) + 1)
            let prefixRange = NSRange(location: lineRange.location, length: prefixPlusSpaceLen)
            let prefixWidth = measuredPrefixWidth(nsString.substring(with: prefixRange), font: baseFont)
            applyHangingIndent(max(20, prefixWidth), to: storage, range: lineRange)
            _ = indentRange

            let stateChar = nsString.substring(with: stateRange)
            if (stateChar == "x" || stateChar == "X"), bodyRange.location != NSNotFound, bodyRange.length > 0 {
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

        if let match = listRegex.firstMatch(in: text, range: lineRange) {
            let markerRange = match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markerRange)

            let prefixEnd = min(NSMaxRange(lineRange), NSMaxRange(markerRange) + 1)
            let prefixRange = NSRange(location: lineRange.location, length: prefixEnd - lineRange.location)
            let prefixWidth = measuredPrefixWidth(nsString.substring(with: prefixRange), font: baseFont)
            applyHangingIndent(max(16, prefixWidth), to: storage, range: lineRange)
            return false
        }

        return false
    }

    // MARK: - Inline Rules

    private func styleInlineElements(
        _ storage: NSTextStorage,
        text: String,
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

        let protectedRanges = skippedLineRanges + codeRanges

        // 2. Bold + Italic (***text***)
        for match in boldItalicRegex.matches(in: text, range: range) {
            let fullRange = match.range(at: 1)
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 6 else { continue }
            applyTrait(.boldFontMask, to: storage, range: fullRange)
            applyTrait(.italicFontMask, to: storage, range: fullRange)
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 3)
        }

        // 3. Bold (**text** or __text__)
        for match in boldRegex.matches(in: text, range: range) {
            let fullRange = match.range
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 4 else { continue }
            applyTrait(.boldFontMask, to: storage, range: fullRange)
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 2)
        }

        // 4. Italic (*text* or _text_)
        for match in italicRegex.matches(in: text, range: range) {
            let fullRange = match.range(at: 1)
            guard !overlapsAny(fullRange, in: protectedRanges), fullRange.length > 2 else { continue }
            applyTrait(.italicFontMask, to: storage, range: fullRange)
            dimMarkers(in: storage, fullRange: fullRange, markerLength: 1)
        }

        // 5. Strikethrough (~~text~~)
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

    private func overlapsAny(_ candidate: NSRange, in ranges: [NSRange]) -> Bool {
        for other in ranges {
            if NSIntersectionRange(candidate, other).length > 0 {
                return true
            }
        }
        return false
    }
}
