import AppKit

/// Pure helper for computing and validating floating panel frames across display changes.
public enum WindowFrameClamper {
    public static let defaultSize = NSSize(width: 420, height: 520)
    public static let minSize = NSSize(width: 280, height: 200)

    /// Computes the initial centered frame within `visibleFrame`, slightly above vertical center.
    public static func defaultFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(defaultSize.width, visibleFrame.width)
        let height = min(defaultSize.height, visibleFrame.height)
        let x = visibleFrame.midX - width * 0.5
        let y = visibleFrame.midY - height * 0.45
        let candidate = NSRect(x: x, y: y, width: width, height: height)
        return clampToFrame(candidate, within: visibleFrame)
    }

    /// Restores a saved frame if meaningfully visible on any active display; otherwise brings it into `fallbackVisibleFrame`.
    public static func clamp(
        _ frame: NSRect,
        to visibleFrames: [NSRect],
        fallbackVisibleFrame: NSRect
    ) -> NSRect {
        var result = frame
        result.size.width = max(result.size.width, minSize.width)
        result.size.height = max(result.size.height, minSize.height)

        let bestScreen = bestMatchingScreen(for: result, in: visibleFrames)
        if let screen = bestScreen {
            if result.size.height > screen.height {
                result.size.height = max(minSize.height, screen.height)
            }
            if result.size.width > screen.width {
                result.size.width = max(minSize.width, screen.width)
            }
            // Keep the top drag bar accessible below the menu bar.
            if result.maxY > screen.maxY {
                result.origin.y = screen.maxY - result.height
            }
            return result
        }

        // Saved frame is off-screen (e.g. disconnected external monitor): clamp size and recenter in fallback.
        let targetWidth = min(result.width, max(minSize.width, fallbackVisibleFrame.width))
        let targetHeight = min(result.height, max(minSize.height, fallbackVisibleFrame.height))
        let centered = NSRect(
            x: fallbackVisibleFrame.midX - targetWidth * 0.5,
            y: fallbackVisibleFrame.midY - targetHeight * 0.45,
            width: targetWidth,
            height: targetHeight
        )
        return clampToFrame(centered, within: fallbackVisibleFrame)
    }

    /// Computes an origin for the Settings window outside `panelFrame` within `visibleFrame` whenever possible.
    public static func settingsOrigin(
        for settingsSize: NSSize,
        avoiding panelFrame: NSRect,
        in visibleFrame: NSRect,
        gap: CGFloat = 16
    ) -> NSPoint {
        func clampedY(_ idealY: CGFloat) -> CGFloat {
            let maxY = max(visibleFrame.minY, visibleFrame.maxY - settingsSize.height)
            return min(max(idealY, visibleFrame.minY), maxY)
        }

        func clampedX(_ idealX: CGFloat) -> CGFloat {
            let maxX = max(visibleFrame.minX, visibleFrame.maxX - settingsSize.width)
            return min(max(idealX, visibleFrame.minX), maxX)
        }

        // 1. Right of floating panel
        let rightX = panelFrame.maxX + gap
        if rightX + settingsSize.width <= visibleFrame.maxX {
            return NSPoint(x: rightX, y: clampedY(panelFrame.maxY - settingsSize.height))
        }

        // 2. Left of floating panel
        let leftX = panelFrame.minX - settingsSize.width - gap
        if leftX >= visibleFrame.minX {
            return NSPoint(x: leftX, y: clampedY(panelFrame.maxY - settingsSize.height))
        }

        // 3. Below floating panel
        let belowY = panelFrame.minY - settingsSize.height - gap
        if belowY >= visibleFrame.minY {
            return NSPoint(x: clampedX(panelFrame.midX - settingsSize.width * 0.5), y: belowY)
        }

        // 4. Above floating panel
        let aboveY = panelFrame.maxY + gap
        if aboveY + settingsSize.height <= visibleFrame.maxY {
            return NSPoint(x: clampedX(panelFrame.midX - settingsSize.width * 0.5), y: aboveY)
        }

        // 5. Fallback: centered inside visible frame (window draws above floating panel via elevated level)
        return NSPoint(
            x: clampedX(visibleFrame.midX - settingsSize.width * 0.5),
            y: clampedY(visibleFrame.midY - settingsSize.height * 0.5)
        )
    }

    private static func bestMatchingScreen(for frame: NSRect, in visibleFrames: [NSRect]) -> NSRect? {
        var bestScreen: NSRect?
        var bestArea: CGFloat = 0

        for screen in visibleFrames {
            let intersection = frame.intersection(screen)
            guard !intersection.isNull else { continue }
            let hasMeaningfulArea = intersection.width >= 100 && intersection.height >= 60
            let titleBarVisible = frame.maxY >= screen.minY + 36 && frame.minY <= screen.maxY
            guard hasMeaningfulArea && titleBarVisible else { continue }

            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }

        return bestScreen
    }

    private static func clampToFrame(_ frame: NSRect, within bounds: NSRect) -> NSRect {
        var result = frame
        if bounds.width > 0 {
            result.size.width = min(result.width, bounds.width)
            result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - result.width)
        }
        if bounds.height > 0 {
            result.size.height = min(result.height, bounds.height)
            result.origin.y = min(max(result.origin.y, bounds.minY), bounds.maxY - result.height)
        }
        return result
    }
}
