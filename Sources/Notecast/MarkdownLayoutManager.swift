import AppKit
import NotecastCore

/// TextKit 1 layout manager adding Bear-style native drawing for fenced code block cards,
/// blockquote vertical accent bars, and crisp vector checkboxes over literal Markdown text.
final class MarkdownLayoutManager: NSLayoutManager {
    var accentColor: NSColor = .controlAccentColor

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

        drawCodeBlockCards(in: storage, charRange: visibleCharRange, container: container, origin: origin)
        drawBlockquoteBars(in: storage, charRange: visibleCharRange, container: container, origin: origin)
        drawCheckboxes(in: storage, charRange: visibleCharRange, container: container, origin: origin)
    }

    // MARK: - Fenced Code Block Cards

    private func drawCodeBlockCards(
        in storage: NSTextStorage,
        charRange: NSRange,
        container: NSTextContainer,
        origin: NSPoint
    ) {
        let containerWidth = max(40, container.containerSize.width)
        let fillColor = NSColor.labelColor.withAlphaComponent(0.055)
        let strokeColor = NSColor.labelColor.withAlphaComponent(0.11)

        // Expand slightly to keep card corners smooth when scrolling partway through a block.
        let scanStart = max(0, charRange.location)
        let scanEnd = min(storage.length, NSMaxRange(charRange))
        guard scanEnd > scanStart else { return }

        storage.enumerateAttribute(
            MarkdownStyler.codeBlockAttribute,
            in: NSRange(location: scanStart, length: scanEnd - scanStart),
            options: []
        ) { value, runRange, _ in
            guard (value as? Bool) == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var blockRect = NSRect.null
            self.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
                blockRect = blockRect.union(rect)
            }
            guard !blockRect.isNull, !blockRect.isEmpty else { return }

            let cardRect = NSRect(
                x: origin.x + 1,
                y: origin.y + blockRect.minY - 2,
                width: max(20, containerWidth - 2),
                height: blockRect.height + 4
            ).integral

            let path = NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7)
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
        container: NSTextContainer,
        origin: NSPoint
    ) {
        let barColor = accentColor.withAlphaComponent(0.72)

        storage.enumerateAttribute(
            MarkdownStyler.blockquoteAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard (value as? Bool) == true else { return }

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var quoteRect = NSRect.null
            self.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
                quoteRect = quoteRect.union(rect)
            }
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

    // MARK: - Custom Vector Checkboxes

    private func drawCheckboxes(
        in storage: NSTextStorage,
        charRange: NSRange,
        container: NSTextContainer,
        origin: NSPoint
    ) {
        storage.enumerateAttribute(
            MarkdownStyler.checkboxStateAttribute,
            in: charRange,
            options: []
        ) { value, runRange, _ in
            guard let state = value as? Int else { return }

            let glyphRange = self.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let rawRect = self.boundingRect(forGlyphRange: glyphRange, in: container)
            guard !rawRect.isEmpty else { return }

            let side = min(14.5, max(11.0, rawRect.height - 4.5)).rounded()
            let boxRect = NSRect(
                x: (origin.x + rawRect.midX - side / 2.0).rounded(),
                y: (origin.y + rawRect.midY - side / 2.0 - 0.5).rounded(),
                width: side,
                height: side
            )

            let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3.5, yRadius: 3.5)

            if state == 1 {
                self.accentColor.setFill()
                boxPath.fill()

                let check = NSBezierPath()
                check.lineWidth = 1.7
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: NSPoint(x: boxRect.minX + side * 0.24, y: boxRect.minY + side * 0.52))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.43, y: boxRect.minY + side * 0.72))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.77, y: boxRect.minY + side * 0.30))

                // Use high-contrast checkmark color (flipped view coordinates: smaller y is top).
                self.checkmarkColor(for: self.accentColor).setStroke()
                check.stroke()
            } else {
                self.accentColor.withAlphaComponent(0.08).setFill()
                boxPath.fill()

                boxPath.lineWidth = 1.35
                self.accentColor.withAlphaComponent(0.86).setStroke()
                boxPath.stroke()
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
