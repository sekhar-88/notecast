import AppKit
import NotecastCore

/// TextKit 1 layout manager adding Bear-style native drawing for fenced code block cards,
/// blockquote vertical accent bars, horizontal separation lines, and circular/rounded checkboxes
/// without any re-entrant layout calls during drawing.
final class MarkdownLayoutManager: NSLayoutManager {
    var accentColor: NSColor = .controlAccentColor
    var checkboxStyle: CheckboxStyle = .circle

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage,
              let container = textContainers.first,
              glyphsToShow.length > 0
        else {
            return
        }

        let visibleCharRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard visibleCharRange.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        drawCodeBlockCards(in: storage, charRange: visibleCharRange, glyphsLimit: NSMaxRange(glyphsToShow), container: container, origin: origin)
        drawBlockquoteBars(in: storage, charRange: visibleCharRange, glyphsLimit: NSMaxRange(glyphsToShow), origin: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage,
              let container = textContainers.first,
              glyphsToShow.length > 0
        else {
            return
        }

        let visibleCharRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard visibleCharRange.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let glyphsLimit = NSMaxRange(glyphsToShow)
        drawHorizontalRules(in: storage, charRange: visibleCharRange, glyphsLimit: glyphsLimit, container: container, origin: origin)
        drawBullets(in: storage, charRange: visibleCharRange, glyphsLimit: glyphsLimit, origin: origin)
        drawCheckboxes(in: storage, charRange: visibleCharRange, glyphsLimit: glyphsLimit, origin: origin)
    }

    /// Computes the exact view-space rect of the drawn checkbox for a checklist marker range,
    /// using non-reentrant layout queries only.
    func checkboxRect(forMarkerRange markerRange: NSRange, origin: NSPoint, glyphsLimit: Int? = nil) -> NSRect? {
        let glyphRange = glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
        let upperBound = glyphsLimit ?? numberOfGlyphs
        guard glyphRange.length > 0, glyphRange.location < upperBound else { return nil }

        let lineRect = lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        guard !lineRect.isEmpty else { return nil }

        let startLoc = location(forGlyphAt: glyphRange.location)
        let textHeight = max(12.0, lineRect.height - 3.5)
        let side = min(15.5, max(12.0, textHeight * 0.78)).rounded()

        return NSRect(
            x: (origin.x + lineRect.minX + startLoc.x + 1.5).rounded(),
            y: (origin.y + lineRect.minY + (textHeight - side) * 0.5 + 0.5).rounded(),
            width: side,
            height: side
        )
    }

    /// Finds the checkbox marker range if `viewPoint` (in `NSTextView` coordinates) hits a drawn checkbox.
    func checkboxMarkerRange(at viewPoint: NSPoint, origin: NSPoint) -> NSRange? {
        guard let storage = textStorage, let container = textContainers.first, storage.length > 0 else {
            return nil
        }

        let containerPoint = NSPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)
        var fraction: CGFloat = 0
        let charIndex = characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < storage.length else { return nil }

        let nsString = storage.string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))

        var matchedRange: NSRange?
        storage.enumerateAttribute(
            MarkdownStyler.checkboxStateAttribute,
            in: lineRange,
            options: []
        ) { value, runRange, stop in
            guard value is Int,
                  let boxRect = self.checkboxRect(forMarkerRange: runRange, origin: origin)
            else {
                return
            }
            if boxRect.insetBy(dx: -5, dy: -4).contains(viewPoint) {
                matchedRange = runRange
                stop.pointee = true
            }
        }
        return matchedRange
    }

    // MARK: - Non-Reentrant Line Fragment Union

    private func unionLineFragmentsWithoutLayout(forGlyphRange glyphRange: NSRange, glyphsLimit: Int) -> NSRect {
        guard glyphRange.length > 0 else { return .null }
        let end = min(NSMaxRange(glyphRange), glyphsLimit)
        var cursor = glyphRange.location
        var unionRect = NSRect.null

        while cursor < end {
            var effective = NSRange(location: NSNotFound, length: 0)
            let rect = lineFragmentRect(
                forGlyphAt: cursor,
                effectiveRange: &effective,
                withoutAdditionalLayout: true
            )
            if !rect.isEmpty {
                unionRect = unionRect.union(rect)
            }
            let next = (effective.location != NSNotFound && effective.length > 0)
                ? NSMaxRange(effective)
                : (cursor + 1)
            guard next > cursor else { break }
            cursor = next
        }
        return unionRect
    }

    // MARK: - Fenced Code Block Cards

    private func drawCodeBlockCards(
        in storage: NSTextStorage,
        charRange: NSRange,
        glyphsLimit: Int,
        container: NSTextContainer,
        origin: NSPoint
    ) {
        let containerWidth = max(40, container.containerSize.width)
        let fillColor = NSColor.labelColor.withAlphaComponent(0.055)
        let strokeColor = NSColor.labelColor.withAlphaComponent(0.11)
        let fullDocRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(
            MarkdownStyler.codeBlockAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard let blockID = value as? Int, blockID > 0 else { return }

            var fullBlockRange = runRange
            _ = storage.attribute(
                MarkdownStyler.codeBlockAttribute,
                at: runRange.location,
                longestEffectiveRange: &fullBlockRange,
                in: fullDocRange
            )

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            let blockRect = self.unionLineFragmentsWithoutLayout(forGlyphRange: glyphRange, glyphsLimit: glyphsLimit)
            guard !blockRect.isNull, !blockRect.isEmpty else { return }

            let includesTop = (runRange.location == fullBlockRange.location)
            let includesBottom = (NSMaxRange(runRange) == NSMaxRange(fullBlockRange))
            let topPad: CGFloat = includesTop ? 2 : 0
            let bottomPad: CGFloat = includesBottom ? 2 : 0

            let cardRect = NSRect(
                x: origin.x + 1,
                y: origin.y + blockRect.minY - topPad,
                width: max(20, containerWidth - 2),
                height: blockRect.height + topPad + bottomPad
            ).integral

            let radius: CGFloat = (includesTop && includesBottom) ? 7 : 0
            let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
            fillColor.setFill()
            path.fill()

            path.lineWidth = 0.75
            strokeColor.setStroke()
            path.stroke()
        }
    }

    // MARK: - Blockquote Vertical Accent Bars

    private func drawBlockquoteBars(
        in storage: NSTextStorage,
        charRange: NSRange,
        glyphsLimit: Int,
        origin: NSPoint
    ) {
        let barColor = accentColor.withAlphaComponent(0.75)

        storage.enumerateAttribute(
            MarkdownStyler.blockquoteAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard (value as? Bool) == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            let quoteRect = self.unionLineFragmentsWithoutLayout(forGlyphRange: glyphRange, glyphsLimit: glyphsLimit)
            guard !quoteRect.isNull, !quoteRect.isEmpty else { return }

            let barRect = NSRect(
                x: origin.x + 3,
                y: origin.y + quoteRect.minY + 2,
                width: 2.5,
                height: max(8, quoteRect.height - 5)
            )
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.25, yRadius: 1.25)
            barColor.setFill()
            barPath.fill()
        }
    }

    // MARK: - Horizontal Separation Lines (`---` / `-- `)

    private func drawHorizontalRules(
        in storage: NSTextStorage,
        charRange: NSRange,
        glyphsLimit: Int,
        container: NSTextContainer,
        origin: NSPoint
    ) {
        let containerWidth = max(40, container.containerSize.width)
        let ruleColor = NSColor.labelColor.withAlphaComponent(0.20)

        storage.enumerateAttribute(
            MarkdownStyler.horizontalRuleAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard (value as? Bool) == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            guard glyphRange.length > 0, glyphRange.location < glyphsLimit else { return }

            let lineRect = self.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            guard !lineRect.isEmpty else { return }

            let y = (origin.y + lineRect.minY + (lineRect.height - 3.5) * 0.5).rounded() + 0.5
            let ruleRect = NSRect(
                x: origin.x + 2,
                y: y,
                width: max(20, containerWidth - 4),
                height: 1.0
            )
            let path = NSBezierPath(roundedRect: ruleRect, xRadius: 0.5, yRadius: 0.5)
            ruleColor.setFill()
            path.fill()
        }
    }

    // MARK: - Custom Vector Bullet Dots

    private func drawBullets(
        in storage: NSTextStorage,
        charRange: NSRange,
        glyphsLimit: Int,
        origin: NSPoint
    ) {
        storage.enumerateAttribute(
            MarkdownStyler.bulletMarkerAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard let depth = value as? Int else { return }

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            guard glyphRange.length > 0, glyphRange.location < glyphsLimit else { return }

            let lineRect = self.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            guard !lineRect.isEmpty else { return }

            let startLoc = self.location(forGlyphAt: glyphRange.location)
            let textHeight = max(12.0, lineRect.height - 3.5)
            let dotSize: CGFloat = min(6.5, max(4.8, textHeight * 0.34)).rounded()
            let dotRect = NSRect(
                x: (origin.x + lineRect.minX + startLoc.x + 2.0).rounded(),
                y: (origin.y + lineRect.minY + (textHeight - dotSize) * 0.5 + 0.5).rounded(),
                width: dotSize,
                height: dotSize
            )
            let dotPath = NSBezierPath(ovalIn: dotRect)

            if depth == 0 {
                self.accentColor.withAlphaComponent(0.90).setFill()
                dotPath.fill()
            } else {
                dotPath.lineWidth = 1.25
                self.accentColor.withAlphaComponent(0.85).setStroke()
                dotPath.stroke()
            }
        }
    }

    // MARK: - Custom Vector Checkboxes

    private func drawCheckboxes(
        in storage: NSTextStorage,
        charRange: NSRange,
        glyphsLimit: Int,
        origin: NSPoint
    ) {
        storage.enumerateAttribute(
            MarkdownStyler.checkboxStateAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard let state = value as? Int,
                  let boxRect = self.checkboxRect(forMarkerRange: runRange, origin: origin, glyphsLimit: glyphsLimit)
            else {
                return
            }

            let side = boxRect.width
            let shapePath: NSBezierPath
            switch self.checkboxStyle {
            case .circle:
                shapePath = NSBezierPath(ovalIn: boxRect)
            case .square:
                shapePath = NSBezierPath(roundedRect: boxRect, xRadius: 3.5, yRadius: 3.5)
            }

            if state == 1 {
                self.accentColor.setFill()
                shapePath.fill()

                let check = NSBezierPath()
                check.lineWidth = 1.65
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: NSPoint(x: boxRect.minX + side * 0.27, y: boxRect.minY + side * 0.52))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.44, y: boxRect.minY + side * 0.70))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.74, y: boxRect.minY + side * 0.32))

                self.checkmarkColor(for: self.accentColor).setStroke()
                check.stroke()
            } else {
                self.accentColor.withAlphaComponent(0.08).setFill()
                shapePath.fill()

                shapePath.lineWidth = 1.4
                self.accentColor.withAlphaComponent(0.88).setStroke()
                shapePath.stroke()
            }
        }
    }

    private func checkmarkColor(for fill: NSColor) -> NSColor {
        guard let rgb = fill.usingColorSpace(.sRGB) else {
            return NSColor.white.withAlphaComponent(0.96)
        }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.62
            ? NSColor.black.withAlphaComponent(0.86)
            : NSColor.white.withAlphaComponent(0.96)
    }
}
