import AppKit
import CoreGraphics

/// Pure-vector brand renderer for Notecast's app bundle icon, floating panel header badge, and monochrome menu bar template icon.
public enum NotecastBrandIcon {
    /// Gradient palette driving Notecast's aurora glow and floating card rim.
    public struct Palette: Sendable {
        public let primary: (r: CGFloat, g: CGFloat, b: CGFloat)
        public let mid: (r: CGFloat, g: CGFloat, b: CGFloat)
        public let secondary: (r: CGFloat, g: CGFloat, b: CGFloat)

        public init(
            primary: (r: CGFloat, g: CGFloat, b: CGFloat),
            mid: (r: CGFloat, g: CGFloat, b: CGFloat),
            secondary: (r: CGFloat, g: CGFloat, b: CGFloat)
        ) {
            self.primary = primary
            self.mid = mid
            self.secondary = secondary
        }

        /// Signature electric cyan-to-violet gradient.
        public static let `default` = Palette(
            primary: (0x22 / 255.0, 0xE5 / 255.0, 0xFF / 255.0),
            mid: (0x3B / 255.0, 0x82 / 255.0, 0xF6 / 255.0),
            secondary: (0xA8 / 255.0, 0x55 / 255.0, 0xF7 / 255.0)
        )

        /// Derives a harmonious gradient palette from an active `NSColor`, falling back to `.default`.
        public static func from(accent: NSColor?) -> Palette {
            guard let srgb = accent?.usingColorSpace(.sRGB) else {
                return .default
            }

            let primary = (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            let shift: CGFloat = hue < 0.25 ? -0.10 : 0.11
            let midColor = NSColor(
                calibratedHue: positiveMod1(hue + shift),
                saturation: max(0.70, saturation),
                brightness: max(0.92, brightness),
                alpha: 1.0
            ).usingColorSpace(.sRGB) ?? srgb

            let secColor = NSColor(
                calibratedHue: positiveMod1(hue + shift * 2.0),
                saturation: max(0.68, saturation * 0.94),
                brightness: max(0.92, brightness),
                alpha: 1.0
            ).usingColorSpace(.sRGB) ?? srgb

            return Palette(
                primary: primary,
                mid: (midColor.redComponent, midColor.greenComponent, midColor.blueComponent),
                secondary: (secColor.redComponent, secColor.greenComponent, secColor.blueComponent)
            )
        }

        private static func positiveMod1(_ value: CGFloat) -> CGFloat {
            let mod = value.truncatingRemainder(dividingBy: 1.0)
            return mod < 0 ? mod + 1.0 : mod
        }
    }

    // MARK: - Public Image & Data APIs

    /// Renders a lossless PNG of the full-color Notecast icon at `pixelSize × pixelSize`.
    public static func renderPNGData(
        pixelSize: Int,
        includeOuterMargin: Bool = true,
        palette: Palette = .default
    ) -> Data? {
        guard pixelSize > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        drawAppIcon(
            in: ctx,
            canvasWidth: CGFloat(pixelSize),
            detailPixels: pixelSize,
            includeOuterMargin: includeOuterMargin,
            palette: palette
        )

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    /// Draws the full-color vector app icon into `ctx` (bottom-left CoreGraphics coordinates) scaled to `canvasWidth`.
    public static func drawAppIcon(
        in ctx: CGContext,
        canvasWidth: CGFloat,
        detailPixels: Int,
        includeOuterMargin: Bool = true,
        palette: Palette = .default,
        dimFactor: CGFloat = 1.0
    ) {
        guard canvasWidth > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return
        }

        ctx.saveGState()
        let scale = canvasWidth / 1024.0
        ctx.scaleBy(x: scale, y: scale)
        let clampedDim = max(0.1, min(1.0, dimFactor))
        let usesTransparencyLayer = clampedDim < 0.999
        if usesTransparencyLayer {
            ctx.setAlpha(clampedDim)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        let squircleRect = includeOuterMargin
            ? CGRect(x: 100, y: 100, width: 824, height: 824)
            : CGRect(x: 28, y: 28, width: 968, height: 968)
        let squircleRadius: CGFloat = includeOuterMargin ? 186 : 216
        let squirclePath = CGPath(
            roundedRect: squircleRect,
            cornerWidth: squircleRadius,
            cornerHeight: squircleRadius,
            transform: nil
        )

        if includeOuterMargin {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -14),
                blur: 24,
                color: cgColor(0, 0, 0, 0.34, space: colorSpace)
            )
            ctx.addPath(squirclePath)
            ctx.setFillColor(cgColor(0x0B / 255.0, 0x0E / 255.0, 0x17 / 255.0, 1.0, space: colorSpace))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Clip all interior icon layers cleanly to the macOS squircle.
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        // Base dark obsidian gradient.
        if let bgGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                cgColor(0x1D / 255.0, 0x23 / 255.0, 0x36 / 255.0, 1.0, space: colorSpace),
                cgColor(0x10 / 255.0, 0x14 / 255.0, 0x20 / 255.0, 1.0, space: colorSpace),
                cgColor(0x07 / 255.0, 0x09 / 255.0, 0x10 / 255.0, 1.0, space: colorSpace)
            ] as CFArray,
            locations: [0.0, 0.52, 1.0]
        ) {
            ctx.drawLinearGradient(
                bgGradient,
                start: CGPoint(x: 512, y: squircleRect.maxY),
                end: CGPoint(x: 512, y: squircleRect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Dual atmospheric aurora glows behind the note cards.
        drawRadialGlow(
            in: ctx,
            space: colorSpace,
            center: CGPoint(x: 360, y: 690),
            radius: 390,
            rgb: palette.primary,
            peakAlpha: 0.28
        )
        drawRadialGlow(
            in: ctx,
            space: colorSpace,
            center: CGPoint(x: 685, y: 315),
            radius: 360,
            rgb: palette.secondary,
            peakAlpha: 0.24
        )

        // Subtle glass specular wash across top-left.
        if let glassSheen = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                cgColor(1, 1, 1, 0.06, space: colorSpace),
                cgColor(1, 1, 1, 0.0, space: colorSpace)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                glassSheen,
                start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
                end: CGPoint(x: 620, y: 420),
                options: []
            )
        }

        // Back ghost outline sheet (echoing Notecast's Ghost Outline Mode).
        drawBackGhostSheet(in: ctx, space: colorSpace, detailPixels: detailPixels, palette: palette)

        // Foreground folded-corner luminous note sheet.
        drawPrimaryNoteSheet(in: ctx, space: colorSpace, detailPixels: detailPixels, palette: palette)

        // Subtle inner rim highlight along the outer squircle.
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.setLineWidth(detailPixels <= 48 ? 16 : 6)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        if let rimGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                cgColor(1, 1, 1, 0.26, space: colorSpace),
                cgColor(1, 1, 1, 0.06, space: colorSpace)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                rimGradient,
                start: CGPoint(x: 512, y: squircleRect.maxY),
                end: CGPoint(x: 512, y: squircleRect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        ctx.restoreGState() // End squircle clip
        if usesTransparencyLayer {
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState() // End root scale/alpha
    }

    /// Returns a crisp Retina-ready full-color NSImage for the floating panel header badge.
    public static func headerIconImage(
        size: NSSize = NSSize(width: 18, height: 18),
        accentColor: NSColor? = nil,
        isActive: Bool = true
    ) -> NSImage {
        let palette = Palette.from(accent: accentColor)
        let dimFactor: CGFloat = isActive ? 1.0 : 0.78
        let detailPixels = max(32, Int(round(max(size.width, size.height) * 2.0)))

        let image = NSImage(size: size, flipped: false) { dstRect in
            guard let ctx = NSGraphicsContext.current?.cgContext else {
                return false
            }
            ctx.interpolationQuality = .high
            drawAppIcon(
                in: ctx,
                canvasWidth: dstRect.width,
                detailPixels: detailPixels,
                includeOuterMargin: false,
                palette: palette,
                dimFactor: dimFactor
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Returns a monochrome macOS template `NSImage` for the top menu bar status item.
    public static func menuBarImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { dstRect in
            guard let ctx = NSGraphicsContext.current?.cgContext else {
                return false
            }
            ctx.saveGState()
            let sx = dstRect.width / 18.0
            let sy = dstRect.height / 18.0
            ctx.scaleBy(x: sx, y: sy)

            let color = NSColor.black.cgColor
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Outer folded-corner note card perimeter (bottom-left coordinate space).
            let cardPath = foldedCardPath(
                rect: CGRect(x: 2.6, y: 1.85, width: 12.8, height: 14.3),
                cornerRadius: 2.5,
                foldSize: 4.1
            )
            ctx.addPath(cardPath)
            ctx.setLineWidth(1.45)
            ctx.strokePath()

            // Dog-ear crease path inside top-right corner.
            let crease = CGMutablePath()
            crease.move(to: CGPoint(x: 11.3, y: 16.15))
            crease.addLine(to: CGPoint(x: 11.3, y: 13.05))
            crease.addQuadCurve(to: CGPoint(x: 12.3, y: 12.05), control: CGPoint(x: 11.3, y: 12.05))
            crease.addLine(to: CGPoint(x: 15.4, y: 12.05))
            ctx.addPath(crease)
            ctx.setLineWidth(1.2)
            ctx.strokePath()

            // Two crisp horizontal note lines.
            let lines = CGMutablePath()
            lines.move(to: CGPoint(x: 5.25, y: 10.2))
            lines.addLine(to: CGPoint(x: 10.1, y: 10.2))
            lines.move(to: CGPoint(x: 5.25, y: 7.0))
            lines.addLine(to: CGPoint(x: 8.95, y: 7.0))
            ctx.addPath(lines)
            ctx.setLineWidth(1.45)
            ctx.strokePath()

            // Crisp 4-point cast spark in bottom-right of the note card.
            let spark = fourPointSparkPath(center: CGPoint(x: 12.15, y: 5.4), outerRadius: 2.5, waistRatio: 0.21)
            ctx.addPath(spark)
            ctx.fillPath()

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Private Vector Helpers

    private static func drawRadialGlow(
        in ctx: CGContext,
        space: CGColorSpace,
        center: CGPoint,
        radius: CGFloat,
        rgb: (r: CGFloat, g: CGFloat, b: CGFloat),
        peakAlpha: CGFloat
    ) {
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                cgColor(rgb.r, rgb.g, rgb.b, peakAlpha, space: space),
                cgColor(rgb.r, rgb.g, rgb.b, 0.0, space: space)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            return
        }

        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
    }

    private static func drawBackGhostSheet(
        in ctx: CGContext,
        space: CGColorSpace,
        detailPixels: Int,
        palette: Palette
    ) {
        ctx.saveGState()
        ctx.translateBy(x: 492, y: 500)
        ctx.rotate(by: -7.5 * .pi / 180.0)
        ctx.translateBy(x: -492, y: -500)

        let backRect = CGRect(x: 294, y: 262, width: 408, height: 494)
        let backPath = CGPath(roundedRect: backRect, cornerWidth: 60, cornerHeight: 60, transform: nil)

        ctx.addPath(backPath)
        ctx.setFillColor(cgColor(1, 1, 1, 0.045, space: space))
        ctx.fillPath()

        ctx.addPath(backPath)
        ctx.setStrokeColor(cgColor(palette.secondary.r, palette.secondary.g, palette.secondary.b, 0.46, space: space))
        ctx.setLineWidth(detailPixels <= 48 ? 16 : 10)
        ctx.strokePath()

        ctx.restoreGState()
    }

    private static func drawPrimaryNoteSheet(
        in ctx: CGContext,
        space: CGColorSpace,
        detailPixels: Int,
        palette: Palette
    ) {
        let cardRect = CGRect(x: 300, y: 252, width: 440, height: 520)
        let cardPath = foldedCardPath(rect: cardRect, cornerRadius: 64, foldSize: 128)

        // Deep drop shadow behind the floating note card.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -22),
            blur: 38,
            color: cgColor(0, 0, 0, 0.62, space: space)
        )
        ctx.addPath(cardPath)
        ctx.setFillColor(cgColor(0x15 / 255.0, 0x1B / 255.0, 0x2B / 255.0, 1.0, space: space))
        ctx.fillPath()
        ctx.restoreGState()

        // Secondary ambient neon bloom around the floating card.
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: 30,
            color: cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 0.34, space: space)
        )
        ctx.addPath(cardPath)
        ctx.setStrokeColor(cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 0.30, space: space))
        ctx.setLineWidth(detailPixels <= 48 ? 20 : 12)
        ctx.strokePath()
        ctx.restoreGState()

        // Frosted obsidian-slate interior gradient.
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()

        if let cardFill = CGGradient(
            colorsSpace: space,
            colors: [
                cgColor(0x22 / 255.0, 0x2B / 255.0, 0x42 / 255.0, 1.0, space: space),
                cgColor(0x15 / 255.0, 0x1B / 255.0, 0x2B / 255.0, 1.0, space: space),
                cgColor(0x0E / 255.0, 0x12 / 255.0, 0x1F / 255.0, 1.0, space: space)
            ] as CFArray,
            locations: [0.0, 0.55, 1.0]
        ) {
            ctx.drawLinearGradient(
                cardFill,
                start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
                end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Folded dog-ear triangular glass flap.
        let flap = CGMutablePath()
        flap.move(to: CGPoint(x: 612, y: 772))
        flap.addLine(to: CGPoint(x: 612, y: 668))
        flap.addQuadCurve(to: CGPoint(x: 636, y: 644), control: CGPoint(x: 612, y: 644))
        flap.addLine(to: CGPoint(x: 740, y: 644))
        flap.closeSubpath()

        ctx.saveGState()
        ctx.addPath(flap)
        ctx.clip()
        if let flapGradient = CGGradient(
            colorsSpace: space,
            colors: [
                cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 0.42, space: space),
                cgColor(palette.secondary.r, palette.secondary.g, palette.secondary.b, 0.24, space: space)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                flapGradient,
                start: CGPoint(x: 612, y: 772),
                end: CGPoint(x: 740, y: 644),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // Inner crease stroke on the folded flap.
        let crease = CGMutablePath()
        crease.move(to: CGPoint(x: 612, y: 766))
        crease.addLine(to: CGPoint(x: 612, y: 668))
        crease.addQuadCurve(to: CGPoint(x: 636, y: 644), control: CGPoint(x: 612, y: 644))
        crease.addLine(to: CGPoint(x: 734, y: 644))
        ctx.addPath(crease)
        ctx.setStrokeColor(cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 0.72, space: space))
        ctx.setLineWidth(detailPixels <= 48 ? 14 : 7)
        ctx.setLineCap(.round)
        ctx.strokePath()

        // Heading pill (glowing accent).
        let headingRect = CGRect(x: 374, y: 594, width: 196, height: 36)
        let headingPath = CGPath(roundedRect: headingRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: 18,
            color: cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 0.55, space: space)
        )
        ctx.addPath(headingPath)
        ctx.setFillColor(cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 1.0, space: space))
        ctx.fillPath()
        ctx.restoreGState()

        // Crisp body lines.
        let line2 = CGPath(roundedRect: CGRect(x: 374, y: 502, width: 290, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.addPath(line2)
        ctx.setFillColor(cgColor(0xF1 / 255.0, 0xF5 / 255.0, 0xFF / 255.0, 0.94, space: space))
        ctx.fillPath()

        let line3 = CGPath(roundedRect: CGRect(x: 374, y: 418, width: 222, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.addPath(line3)
        ctx.setFillColor(cgColor(0xCB / 255.0, 0xD5 / 255.0, 0xE1 / 255.0, 0.76, space: space))
        ctx.fillPath()

        if detailPixels > 32 {
            let line4 = CGPath(roundedRect: CGRect(x: 374, y: 334, width: 134, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil)
            ctx.addPath(line4)
            ctx.setFillColor(cgColor(0x94 / 255.0, 0xA3 / 255.0, 0xB8 / 255.0, 0.56, space: space))
            ctx.fillPath()
        }

        // Signature 4-point "cast" spark in bottom-right of the note card.
        let sparkPath = fourPointSparkPath(center: CGPoint(x: 626, y: 358), outerRadius: 50, waistRatio: 0.16)
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: 20,
            color: cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 0.72, space: space)
        )
        ctx.addPath(sparkPath)
        ctx.clip()
        if let sparkGradient = CGGradient(
            colorsSpace: space,
            colors: [
                cgColor(0xF0 / 255.0, 0xFF / 255.0, 0xFF / 255.0, 1.0, space: space),
                cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 1.0, space: space)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                sparkGradient,
                start: CGPoint(x: 626, y: 408),
                end: CGPoint(x: 626, y: 308),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        ctx.restoreGState() // End card fill clip

        // Signature electric cyan-to-violet neon border stroke around the entire folded note sheet.
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.setLineWidth(detailPixels <= 48 ? 28 : 18)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.replacePathWithStrokedPath()
        ctx.clip()

        if let neonGradient = CGGradient(
            colorsSpace: space,
            colors: [
                cgColor(palette.primary.r, palette.primary.g, palette.primary.b, 1.0, space: space),
                cgColor(palette.mid.r, palette.mid.g, palette.mid.b, 1.0, space: space),
                cgColor(palette.secondary.r, palette.secondary.g, palette.secondary.b, 1.0, space: space)
            ] as CFArray,
            locations: [0.0, 0.5, 1.0]
        ) {
            ctx.drawLinearGradient(
                neonGradient,
                start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
                end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    private static func foldedCardPath(rect: CGRect, cornerRadius r: CGFloat, foldSize fold: CGFloat) -> CGPath {
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let path = CGMutablePath()
        path.move(to: CGPoint(x: minX + r, y: maxY))
        path.addLine(to: CGPoint(x: maxX - fold, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - fold))
        path.addLine(to: CGPoint(x: maxX, y: minY + r))
        path.addArc(
            center: CGPoint(x: maxX - r, y: minY + r),
            radius: r,
            startAngle: 0,
            endAngle: -.pi * 0.5,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: minX + r, y: minY))
        path.addArc(
            center: CGPoint(x: minX + r, y: minY + r),
            radius: r,
            startAngle: -.pi * 0.5,
            endAngle: -.pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: minX, y: maxY - r))
        path.addArc(
            center: CGPoint(x: minX + r, y: maxY - r),
            radius: r,
            startAngle: .pi,
            endAngle: .pi * 0.5,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private static func fourPointSparkPath(center: CGPoint, outerRadius r: CGFloat, waistRatio: CGFloat) -> CGPath {
        let w = r * waistRatio
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: center.y + r))
        path.addCurve(
            to: CGPoint(x: center.x + r, y: center.y),
            control1: CGPoint(x: center.x, y: center.y + w),
            control2: CGPoint(x: center.x + w, y: center.y)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - r),
            control1: CGPoint(x: center.x + w, y: center.y),
            control2: CGPoint(x: center.x, y: center.y - w)
        )
        path.addCurve(
            to: CGPoint(x: center.x - r, y: center.y),
            control1: CGPoint(x: center.x, y: center.y - w),
            control2: CGPoint(x: center.x - w, y: center.y)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y + r),
            control1: CGPoint(x: center.x - w, y: center.y),
            control2: CGPoint(x: center.x, y: center.y + w)
        )
        path.closeSubpath()
        return path
    }

    private static func cgColor(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        _ alpha: CGFloat,
        space: CGColorSpace
    ) -> CGColor {
        CGColor(colorSpace: space, components: [red, green, blue, alpha]) ?? NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor
    }
}
