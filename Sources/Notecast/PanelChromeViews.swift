import AppKit
import NotecastCore
import QuartzCore

/// Title bar icon button with borderless hover tint, tactile press fade, and bottom active underline indicator.
@MainActor
final class HeaderIconButton: NSButton {
    var isActiveState = false {
        didSet {
            if isActiveState != oldValue {
                updateVisualState(animated: true)
            }
        }
    }

    var restTintColor: NSColor? {
        didSet { updateVisualState(animated: false) }
    }

    var hoverTintOverride: NSColor? {
        didSet { updateVisualState(animated: false) }
    }

    var activeAccentColor: NSColor = .controlAccentColor {
        didSet { updateVisualState(animated: false) }
    }

    private let activeIndicatorLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        showsBorderOnlyWhileMouseInside = false
        focusRingType = .none
        bezelStyle = .regularSquare
        imageScaling = .scaleProportionallyDown
        (cell as? NSButtonCell)?.highlightsBy = []
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil

        activeIndicatorLayer.cornerRadius = 1
        activeIndicatorLayer.opacity = 0
        layer?.addSublayer(activeIndicatorLayer)
        updateVisualState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                updateVisualState(animated: false)
            }
        }
    }

    override func layout() {
        super.layout()
        let y: CGFloat = isFlipped ? (bounds.height - 3.5) : 1.5
        activeIndicatorLayer.frame = CGRect(
            x: floor((bounds.width - 10) * 0.5),
            y: y,
            width: 10,
            height: 2
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualState(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateVisualState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateVisualState(animated: true)
    }

    func resetHover() {
        guard isHovered else { return }
        isHovered = false
        updateVisualState(animated: false)
    }

    private func updateVisualState(animated: Bool) {
        let tintColor: NSColor
        let targetAlpha: CGFloat
        let indicatorOpacity: Float

        if isHighlighted {
            targetAlpha = 0.55
            tintColor = isActiveState ? activeAccentColor : (hoverTintOverride ?? .labelColor)
            indicatorOpacity = isActiveState ? 1.0 : 0.0
        } else if isActiveState {
            targetAlpha = 1.0
            tintColor = activeAccentColor
            indicatorOpacity = 1.0
        } else if isHovered {
            targetAlpha = 1.0
            tintColor = hoverTintOverride ?? .labelColor
            indicatorOpacity = 0.0
        } else {
            targetAlpha = 1.0
            tintColor = restTintColor ?? .secondaryLabelColor
            indicatorOpacity = 0.0
        }

        let apply = {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.layer?.borderColor = nil
            self.activeIndicatorLayer.backgroundColor = self.activeAccentColor.cgColor
            self.activeIndicatorLayer.opacity = indicatorOpacity
            self.contentTintColor = tintColor
            self.alphaValue = targetAlpha
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            apply()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        }
    }
}

/// Non-interactive subview that delegates all hits to its parent view.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Wrapper container that forwards hits normally when awake and passes interior clicks through when ghosted.
@MainActor
final class GhostContentWrapperView: NSView {
    var isGhosted = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isGhosted ? nil : super.hitTest(point)
    }
}

/// Feathered right-side dual-tone click-to-wake zone in Ghost Outline Mode; fades smoothly from 0 alpha so the left side remains click-through.
@MainActor
final class GhostWakeZoneView: NSView {
    var onWake: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private let contrastGradientLayer = CAGradientLayer()
    private let accentGradientLayer = CAGradientLayer()
    private let gripPill = PassThroughView()
    private var trackingArea: NSTrackingArea?

    private var neonGlowEnabled = true
    private var accentColor = NeonAccent.cyan.nsColor
    private var isHovered = false

    private var isTrackingPress = false
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDragDuringPress = false
    private let dragThreshold: CGFloat = 3.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        contrastGradientLayer.frame = bounds
        accentGradientLayer.frame = bounds
        if !gripPill.bounds.isEmpty {
            gripPill.layer?.shadowPath = CGPath(
                roundedRect: gripPill.bounds,
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil
            )
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDragDuringPress = false
        isTrackingPress = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress,
              let window,
              let startMouse = dragStartScreenPoint,
              let startOrigin = dragStartWindowOrigin
        else {
            return
        }

        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y
        if !didDragDuringPress && hypot(dx, dy) >= dragThreshold {
            didDragDuringPress = true
            NSCursor.closedHand.push()
        }
        if didDragDuringPress {
            window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        isTrackingPress = false

        let startMouse = dragStartScreenPoint
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil

        let finalDist: CGFloat
        if let startMouse {
            let currentMouse = NSEvent.mouseLocation
            finalDist = hypot(currentMouse.x - startMouse.x, currentMouse.y - startMouse.y)
        } else {
            finalDist = 0
        }

        if didDragDuringPress || finalDist >= dragThreshold {
            if didDragDuringPress {
                NSCursor.pop()
            }
            didDragDuringPress = false
            onDragEnded?()
            return
        }

        didDragDuringPress = false
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            onWake?()
        }
    }

    func resetHover() {
        guard isHovered else { return }
        isHovered = false
        applyAppearance(animated: false)
    }

    func update(neonGlowEnabled: Bool, accentColor: NSColor, animated: Bool) {
        self.neonGlowEnabled = neonGlowEnabled
        self.accentColor = accentColor
        applyAppearance(animated: animated)
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        let stops: [NSNumber] = [0.0, 0.12, 0.30, 0.54, 0.78, 1.0]

        contrastGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        contrastGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        contrastGradientLayer.locations = stops
        layer?.addSublayer(contrastGradientLayer)

        accentGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        accentGradientLayer.locations = stops
        layer?.addSublayer(accentGradientLayer)

        gripPill.translatesAutoresizingMaskIntoConstraints = false
        gripPill.wantsLayer = true
        gripPill.layer?.cornerRadius = 2
        gripPill.layer?.borderWidth = 0.75
        gripPill.layer?.borderColor = NSColor.black.withAlphaComponent(0.45).cgColor
        gripPill.layer?.shadowOffset = .zero
        gripPill.layer?.shadowRadius = 4
        addSubview(gripPill)

        NSLayoutConstraint.activate([
            gripPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            gripPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            gripPill.widthAnchor.constraint(equalToConstant: 4),
            gripPill.heightAnchor.constraint(equalToConstant: 34)
        ])

        applyAppearance(animated: false)
    }

    private func applyAppearance(animated: Bool) {
        let slateBase = NSColor(srgbRed: 0x14 / 255.0, green: 0x19 / 255.0, blue: 0x24 / 255.0, alpha: 1.0)
        let contrastAlphas: [CGFloat] = isHovered
            ? [0.0, 0.022, 0.065, 0.12, 0.175, 0.22]
            : [0.0, 0.015, 0.045, 0.085, 0.125, 0.16]
        let accentBase = neonGlowEnabled ? accentColor : NSColor.white
        let accentAlphas: [CGFloat] = isHovered
            ? [0.0, 0.018, 0.052, 0.10, 0.165, 0.22]
            : [0.0, 0.012, 0.035, 0.068, 0.105, 0.15]

        let apply = {
            self.contrastGradientLayer.colors = contrastAlphas.map { slateBase.withAlphaComponent($0).cgColor }
            self.accentGradientLayer.colors = accentAlphas.map { accentBase.withAlphaComponent($0).cgColor }

            if self.neonGlowEnabled {
                self.gripPill.layer?.backgroundColor = self.accentColor.withAlphaComponent(self.isHovered ? 0.96 : 0.76).cgColor
                self.gripPill.layer?.shadowColor = self.accentColor.cgColor
                self.gripPill.layer?.shadowOpacity = self.isHovered ? 0.6 : 0.38
            } else {
                self.gripPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(self.isHovered ? 0.90 : 0.70).cgColor
                self.gripPill.layer?.shadowColor = NSColor.black.cgColor
                self.gripPill.layer?.shadowOpacity = 0.28
            }
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            apply()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        }
    }
}

/// Scroll view that keeps its hosted `NSTextView` and `NSTextContainer` width synced to clip bounds for reliable word wrap.
@MainActor
final class WrappingScrollView: NSScrollView {
    override func layout() {
        super.layout()
        syncTextViewWidth()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncTextViewWidth()
    }

    private func syncTextViewWidth() {
        guard let textView = documentView as? NSTextView else { return }
        let clipBounds = contentView.bounds
        let clipWidth = max(100, clipBounds.width)

        if abs(textView.frame.width - clipWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: clipWidth, height: max(textView.frame.height, clipBounds.height)))
        }

        let insetX = textView.textContainerInset.width * 2
        let targetContainerWidth = max(40, clipWidth - insetX)
        if let textContainer = textView.textContainer,
           abs(textContainer.containerSize.width - targetContainerWidth) > 0.5
        {
            textContainer.containerSize = NSSize(width: targetContainerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
    }
}

/// Header divider rendering a luminous neon hairline gradient when active.
@MainActor
final class SeparatorGlowView: NSView {
    private let glowLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        glowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(glowLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        glowLayer.frame = bounds
    }

    func update(glowActive: Bool, accentColor: NSColor, surfaceStyle: SurfaceStyle) {
        glowLayer.frame = bounds
        if glowActive {
            glowLayer.isHidden = false
            glowLayer.colors = [
                accentColor.withAlphaComponent(0.12).cgColor,
                accentColor.withAlphaComponent(0.9).cgColor,
                accentColor.withAlphaComponent(0.12).cgColor
            ]
            layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            glowLayer.isHidden = true
            layer?.backgroundColor = surfaceStyle.calmSeparatorColor.cgColor
        }
    }
}

/// Non-interactive overlay drawing active neon glow, calm borders, or dual-contrast Ghost Outline reticle arcs.
@MainActor
final class NeonGlowOverlayView: NSView {
    private let innerGlowLayer = CAShapeLayer()
    private let ghostContrastOutlineLayer = CAShapeLayer()
    private let ghostOutlineLayer = CAShapeLayer()
    private let ghostContrastCornersLayer = CAShapeLayer()
    private let ghostCornersLayer = CAShapeLayer()
    private var lastPathBounds: NSRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = panelCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        innerGlowLayer.fillRule = .evenOdd
        innerGlowLayer.shadowOffset = .zero
        innerGlowLayer.shadowRadius = 12
        layer?.addSublayer(innerGlowLayer)

        ghostContrastOutlineLayer.fillColor = nil
        ghostContrastOutlineLayer.lineWidth = 2.5
        ghostContrastOutlineLayer.lineDashPattern = [5, 4]
        ghostContrastOutlineLayer.strokeColor = NSColor.black.withAlphaComponent(0.38).cgColor
        ghostContrastOutlineLayer.opacity = 0
        layer?.addSublayer(ghostContrastOutlineLayer)

        ghostOutlineLayer.fillColor = nil
        ghostOutlineLayer.lineWidth = 1.25
        ghostOutlineLayer.lineDashPattern = [5, 4]
        ghostOutlineLayer.opacity = 0
        layer?.addSublayer(ghostOutlineLayer)

        ghostContrastCornersLayer.fillColor = nil
        ghostContrastCornersLayer.lineWidth = 3.75
        ghostContrastCornersLayer.lineCap = .round
        ghostContrastCornersLayer.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
        ghostContrastCornersLayer.opacity = 0
        layer?.addSublayer(ghostContrastCornersLayer)

        ghostCornersLayer.fillColor = nil
        ghostCornersLayer.lineWidth = 2.0
        ghostCornersLayer.lineCap = .round
        ghostCornersLayer.shadowOffset = .zero
        ghostCornersLayer.shadowRadius = 4
        ghostCornersLayer.opacity = 0
        layer?.addSublayer(ghostCornersLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    func update(
        isActive: Bool,
        isGhosted: Bool,
        neonGlowEnabled: Bool,
        accentColor: NSColor,
        surfaceStyle: SurfaceStyle,
        animated: Bool
    ) {
        updatePaths()

        let applyChanges = {
            if isGhosted {
                self.layer?.borderWidth = 0
                self.innerGlowLayer.shadowOpacity = 0.0

                self.ghostContrastOutlineLayer.opacity = 1.0

                self.ghostOutlineLayer.strokeColor = neonGlowEnabled
                    ? accentColor.withAlphaComponent(0.78).cgColor
                    : NSColor.white.withAlphaComponent(0.80).cgColor
                self.ghostOutlineLayer.opacity = 1.0

                self.ghostContrastCornersLayer.opacity = 1.0

                self.ghostCornersLayer.strokeColor = neonGlowEnabled
                    ? accentColor.withAlphaComponent(0.95).cgColor
                    : NSColor.white.withAlphaComponent(0.90).cgColor
                self.ghostCornersLayer.shadowColor = neonGlowEnabled
                    ? accentColor.cgColor
                    : NSColor.black.cgColor
                self.ghostCornersLayer.shadowOpacity = neonGlowEnabled ? 0.55 : 0.25
                self.ghostCornersLayer.opacity = 1.0
            } else {
                self.ghostContrastOutlineLayer.opacity = 0.0
                self.ghostOutlineLayer.opacity = 0.0
                self.ghostContrastCornersLayer.opacity = 0.0
                self.ghostCornersLayer.opacity = 0.0

                if isActive && neonGlowEnabled {
                    self.layer?.borderWidth = 1.5
                    self.layer?.borderColor = accentColor.withAlphaComponent(0.95).cgColor
                    self.innerGlowLayer.fillColor = accentColor.cgColor
                    self.innerGlowLayer.shadowColor = accentColor.cgColor
                    self.innerGlowLayer.shadowOpacity = 0.55
                } else {
                    self.layer?.borderWidth = 0.75
                    self.layer?.borderColor = surfaceStyle.calmBorderColor.cgColor
                    self.innerGlowLayer.shadowOpacity = 0.0
                }
            }
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            applyChanges()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyChanges()
            CATransaction.commit()
        }
    }

    private func updatePaths() {
        guard !bounds.isEmpty, bounds != lastPathBounds else { return }
        lastPathBounds = bounds
        innerGlowLayer.frame = bounds
        ghostContrastOutlineLayer.frame = bounds
        ghostOutlineLayer.frame = bounds
        ghostContrastCornersLayer.frame = bounds
        ghostCornersLayer.frame = bounds

        let outerRect = bounds.insetBy(dx: -24, dy: -24)
        let innerGlowPath = CGMutablePath()
        innerGlowPath.addRect(outerRect)
        innerGlowPath.addPath(CGPath(roundedRect: bounds, cornerWidth: panelCornerRadius, cornerHeight: panelCornerRadius, transform: nil))
        innerGlowLayer.path = innerGlowPath
        // Intentionally omit `innerGlowLayer.shadowPath`: CALayer.shadowPath uses non-zero winding
        // and ignores `fillRule = .evenOdd`, which would fill the entire editor interior with shadow.

        let r = bounds.insetBy(dx: 1.0, dy: 1.0)
        let cr = max(2, panelCornerRadius - 1.0)
        let arm: CGFloat = 12
        let gap: CGFloat = 4
        let startX = r.minX + cr + arm + gap
        let endX = r.maxX - cr - arm - gap

        // Top and bottom dotted bars only (left/right vertical dotted bars hidden in Ghost Outline Mode).
        let outlinePath = CGMutablePath()
        if startX < endX {
            outlinePath.move(to: CGPoint(x: startX, y: r.maxY))
            outlinePath.addLine(to: CGPoint(x: endX, y: r.maxY))
            outlinePath.move(to: CGPoint(x: startX, y: r.minY))
            outlinePath.addLine(to: CGPoint(x: endX, y: r.minY))
        }
        ghostContrastOutlineLayer.path = outlinePath
        ghostOutlineLayer.path = outlinePath

        let cornersPath = CGMutablePath()

        // Bottom-left
        cornersPath.move(to: CGPoint(x: r.minX, y: r.minY + cr + arm))
        cornersPath.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        cornersPath.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + cr, y: r.minY), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.minX + cr + arm, y: r.minY))

        // Bottom-right
        cornersPath.move(to: CGPoint(x: r.maxX - cr - arm, y: r.minY))
        cornersPath.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        cornersPath.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + cr), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.maxX, y: r.minY + cr + arm))

        // Top-right
        cornersPath.move(to: CGPoint(x: r.maxX, y: r.maxY - cr - arm))
        cornersPath.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cr))
        cornersPath.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - cr, y: r.maxY), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.maxX - cr - arm, y: r.maxY))

        // Top-left
        cornersPath.move(to: CGPoint(x: r.minX + cr + arm, y: r.maxY))
        cornersPath.addLine(to: CGPoint(x: r.minX + cr, y: r.maxY))
        cornersPath.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - cr), radius: cr)
        cornersPath.addLine(to: CGPoint(x: r.minX, y: r.maxY - cr - arm))

        ghostContrastCornersLayer.path = cornersPath
        ghostCornersLayer.path = cornersPath
        ghostCornersLayer.shadowPath = cornersPath.copy(
            strokingWithWidth: ghostCornersLayer.lineWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 4
        )
    }
}

/// Draggable header bar that lets the user reposition the borderless floating panel.
@MainActor
final class HeaderDragView: NSView {
    var onDragEnded: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        onDragEnded?()
    }
}
