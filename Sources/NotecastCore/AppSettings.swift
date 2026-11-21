import AppKit
import Foundation

/// Controls the floating panel background theme (curated opaque dark/light surfaces or translucent HUD).
public enum SurfaceStyle: String, Codable, CaseIterable, Sendable {
    case charcoal
    case graphite
    case immersiveBlack
    case midnightSlate
    case deepIndigo
    case nordicBlue
    case warmEspresso
    case deepForest
    case plumNoir
    case warmPaper
    case coolMist
    case translucentHUD

    public var displayName: String {
        switch self {
        case .charcoal: return "Charcoal"
        case .graphite: return "Graphite"
        case .immersiveBlack: return "Pure Black"
        case .midnightSlate: return "Midnight Slate"
        case .deepIndigo: return "Deep Indigo"
        case .nordicBlue: return "Nordic Blue"
        case .warmEspresso: return "Warm Espresso"
        case .deepForest: return "Deep Forest"
        case .plumNoir: return "Plum Noir"
        case .warmPaper: return "Warm Paper"
        case .coolMist: return "Cool Mist"
        case .translucentHUD: return "Translucent HUD"
        }
    }

    public var isOpaque: Bool {
        self != .translucentHUD
    }

    public var isLight: Bool {
        self == .warmPaper || self == .coolMist
    }

    public var backgroundColor: NSColor? {
        switch self {
        case .charcoal:
            return NSColor(srgbRed: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0, alpha: 1.0)
        case .graphite:
            return NSColor(srgbRed: 0x22 / 255.0, green: 0x24 / 255.0, blue: 0x2A / 255.0, alpha: 1.0)
        case .immersiveBlack:
            return NSColor.black
        case .midnightSlate:
            return NSColor(srgbRed: 0x17 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1.0)
        case .deepIndigo:
            return NSColor(srgbRed: 0x19 / 255.0, green: 0x17 / 255.0, blue: 0x2B / 255.0, alpha: 1.0)
        case .nordicBlue:
            return NSColor(srgbRed: 0x1D / 255.0, green: 0x27 / 255.0, blue: 0x33 / 255.0, alpha: 1.0)
        case .warmEspresso:
            return NSColor(srgbRed: 0x1A / 255.0, green: 0x17 / 255.0, blue: 0x15 / 255.0, alpha: 1.0)
        case .deepForest:
            return NSColor(srgbRed: 0x12 / 255.0, green: 0x1A / 255.0, blue: 0x17 / 255.0, alpha: 1.0)
        case .plumNoir:
            return NSColor(srgbRed: 0x1F / 255.0, green: 0x15 / 255.0, blue: 0x20 / 255.0, alpha: 1.0)
        case .warmPaper:
            return NSColor(srgbRed: 0xF7 / 255.0, green: 0xF5 / 255.0, blue: 0xF0 / 255.0, alpha: 1.0)
        case .coolMist:
            return NSColor(srgbRed: 0xEE / 255.0, green: 0xF2 / 255.0, blue: 0xF6 / 255.0, alpha: 1.0)
        case .translucentHUD:
            return nil
        }
    }

    public var headerBackgroundColor: NSColor? {
        switch self {
        case .charcoal:
            return NSColor(srgbRed: 0x1B / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0, alpha: 1.0)
        case .graphite:
            return NSColor(srgbRed: 0x2B / 255.0, green: 0x2E / 255.0, blue: 0x36 / 255.0, alpha: 1.0)
        case .immersiveBlack:
            return NSColor(srgbRed: 0x08 / 255.0, green: 0x08 / 255.0, blue: 0x0C / 255.0, alpha: 1.0)
        case .midnightSlate:
            return NSColor(srgbRed: 0x1E / 255.0, green: 0x25 / 255.0, blue: 0x33 / 255.0, alpha: 1.0)
        case .deepIndigo:
            return NSColor(srgbRed: 0x22 / 255.0, green: 0x1F / 255.0, blue: 0x38 / 255.0, alpha: 1.0)
        case .nordicBlue:
            return NSColor(srgbRed: 0x25 / 255.0, green: 0x31 / 255.0, blue: 0x40 / 255.0, alpha: 1.0)
        case .warmEspresso:
            return NSColor(srgbRed: 0x22 / 255.0, green: 0x1E / 255.0, blue: 0x1B / 255.0, alpha: 1.0)
        case .deepForest:
            return NSColor(srgbRed: 0x18 / 255.0, green: 0x23 / 255.0, blue: 0x1F / 255.0, alpha: 1.0)
        case .plumNoir:
            return NSColor(srgbRed: 0x2A / 255.0, green: 0x1D / 255.0, blue: 0x2B / 255.0, alpha: 1.0)
        case .warmPaper:
            return NSColor(srgbRed: 0xEF / 255.0, green: 0xEC / 255.0, blue: 0xE4 / 255.0, alpha: 1.0)
        case .coolMist:
            return NSColor(srgbRed: 0xE3 / 255.0, green: 0xE9 / 255.0, blue: 0xF0 / 255.0, alpha: 1.0)
        case .translucentHUD:
            return nil
        }
    }

    public var paletteCardColor: NSColor {
        switch self {
        case .charcoal:
            return NSColor(srgbRed: 0x19 / 255.0, green: 0x1B / 255.0, blue: 0x22 / 255.0, alpha: 0.98)
        case .graphite:
            return NSColor(srgbRed: 0x26 / 255.0, green: 0x29 / 255.0, blue: 0x30 / 255.0, alpha: 0.98)
        case .immersiveBlack:
            return NSColor(srgbRed: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x10 / 255.0, alpha: 0.98)
        case .midnightSlate:
            return NSColor(srgbRed: 0x1B / 255.0, green: 0x21 / 255.0, blue: 0x2E / 255.0, alpha: 0.98)
        case .deepIndigo:
            return NSColor(srgbRed: 0x1E / 255.0, green: 0x1B / 255.0, blue: 0x33 / 255.0, alpha: 0.98)
        case .nordicBlue:
            return NSColor(srgbRed: 0x21 / 255.0, green: 0x2C / 255.0, blue: 0x3A / 255.0, alpha: 0.98)
        case .warmEspresso:
            return NSColor(srgbRed: 0x1F / 255.0, green: 0x1B / 255.0, blue: 0x18 / 255.0, alpha: 0.98)
        case .deepForest:
            return NSColor(srgbRed: 0x16 / 255.0, green: 0x20 / 255.0, blue: 0x1C / 255.0, alpha: 0.98)
        case .plumNoir:
            return NSColor(srgbRed: 0x25 / 255.0, green: 0x19 / 255.0, blue: 0x26 / 255.0, alpha: 0.98)
        case .warmPaper:
            return NSColor(srgbRed: 0xFB / 255.0, green: 0xF9 / 255.0, blue: 0xF5 / 255.0, alpha: 0.98)
        case .coolMist:
            return NSColor(srgbRed: 0xF5 / 255.0, green: 0xF8 / 255.0, blue: 0xFB / 255.0, alpha: 0.98)
        case .translucentHUD:
            return NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        }
    }

    public var calmBorderColor: NSColor {
        if self == .translucentHUD {
            return NSColor.separatorColor.withAlphaComponent(0.55)
        }
        if isLight {
            return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.14)
        }
        return NSColor(white: 1.0, alpha: 0.14)
    }

    public var calmSeparatorColor: NSColor {
        if self == .translucentHUD {
            return NSColor.separatorColor.withAlphaComponent(0.35)
        }
        if isLight {
            return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
        }
        return NSColor(white: 1.0, alpha: 0.12)
    }

    public func next() -> SurfaceStyle {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .charcoal }
        return all[(idx + 1) % all.count]
    }
}

/// Neon glow accent color used when the floating panel is active.
public enum NeonAccent: String, Codable, CaseIterable, Sendable {
    case cyan
    case violet
    case magenta
    case emerald
    case amber

    public var displayName: String {
        switch self {
        case .cyan: return "Neon Cyan"
        case .violet: return "Neon Violet"
        case .magenta: return "Neon Magenta"
        case .emerald: return "Neon Emerald"
        case .amber: return "Neon Amber"
        }
    }

    public var nsColor: NSColor {
        switch self {
        case .cyan: return NSColor(srgbRed: 0.0, green: 0.941, blue: 1.0, alpha: 1.0) // #00F0FF
        case .violet: return NSColor(srgbRed: 0.722, green: 0.302, blue: 1.0, alpha: 1.0) // #B84DFF
        case .magenta: return NSColor(srgbRed: 1.0, green: 0.180, blue: 0.592, alpha: 1.0) // #FF2E97
        case .emerald: return NSColor(srgbRed: 0.0, green: 1.0, blue: 0.616, alpha: 1.0) // #00FF9D
        case .amber: return NSColor(srgbRed: 1.0, green: 0.722, blue: 0.0, alpha: 1.0) // #FFB800
        }
    }

    public func next() -> NeonAccent {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .cyan }
        return all[(idx + 1) % all.count]
    }
}

/// Persists user preferences and the last floating panel frame in `UserDefaults`.
@MainActor
public final class AppSettings {
    private enum Keys {
        static let hotKey = "notecast.hotKey"
        static let alwaysOnTop = "notecast.alwaysOnTop"
        static let followAllSpaces = "notecast.followAllSpaces"
        static let windowOpacity = "notecast.windowOpacity"
        static let fontSize = "notecast.fontSize"
        static let savedWindowFrame = "notecast.savedWindowFrame"
        static let surfaceStyle = "notecast.surfaceStyle"
        static let neonGlowEnabled = "notecast.neonGlowEnabled"
        static let neonAccent = "notecast.neonAccent"
        static let fontFamily = "notecast.fontFamily"
        static let ghostOnUnfocus = "notecast.ghostOnUnfocus"
    }

    public static let minOpacity: Double = 0.65
    public static let maxOpacity: Double = 1.0
    public static let defaultOpacity: Double = 0.96

    public static let minFontSize: CGFloat = 11
    public static let maxFontSize: CGFloat = 26
    public static let defaultFontSize: CGFloat = 14

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hotKey: HotKeyCombo {
        get {
            guard let data = defaults.data(forKey: Keys.hotKey),
                  let decoded = try? JSONDecoder().decode(HotKeyCombo.self, from: data)
            else {
                return .defaultToggle
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }

    public var alwaysOnTop: Bool {
        get {
            guard defaults.object(forKey: Keys.alwaysOnTop) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.alwaysOnTop)
        }
        set {
            defaults.set(newValue, forKey: Keys.alwaysOnTop)
        }
    }

    public var followAllSpaces: Bool {
        get {
            guard defaults.object(forKey: Keys.followAllSpaces) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.followAllSpaces)
        }
        set {
            defaults.set(newValue, forKey: Keys.followAllSpaces)
        }
    }

    public var windowOpacity: Double {
        get {
            guard defaults.object(forKey: Keys.windowOpacity) != nil else {
                return Self.defaultOpacity
            }
            return Self.clampOpacity(defaults.double(forKey: Keys.windowOpacity))
        }
        set {
            defaults.set(Self.clampOpacity(newValue), forKey: Keys.windowOpacity)
        }
    }

    public var fontSize: CGFloat {
        get {
            guard defaults.object(forKey: Keys.fontSize) != nil else {
                return Self.defaultFontSize
            }
            return Self.clampFontSize(CGFloat(defaults.double(forKey: Keys.fontSize)))
        }
        set {
            defaults.set(Double(Self.clampFontSize(newValue)), forKey: Keys.fontSize)
        }
    }

    public var savedWindowFrame: NSRect? {
        get {
            guard let array = defaults.array(forKey: Keys.savedWindowFrame) as? [Double],
                  array.count == 4,
                  array.allSatisfy(\.isFinite)
            else {
                return nil
            }
            let rect = NSRect(x: array[0], y: array[1], width: array[2], height: array[3])
            guard rect.width > 0, rect.height > 0 else { return nil }
            return rect
        }
        set {
            if let frame = newValue {
                defaults.set(
                    [Double(frame.origin.x), Double(frame.origin.y), Double(frame.size.width), Double(frame.size.height)],
                    forKey: Keys.savedWindowFrame
                )
            } else {
                defaults.removeObject(forKey: Keys.savedWindowFrame)
            }
        }
    }

    public var surfaceStyle: SurfaceStyle {
        get {
            guard let raw = defaults.string(forKey: Keys.surfaceStyle),
                  let style = SurfaceStyle(rawValue: raw)
            else {
                return .charcoal
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.surfaceStyle)
        }
    }

    public var neonGlowEnabled: Bool {
        get {
            guard defaults.object(forKey: Keys.neonGlowEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.neonGlowEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.neonGlowEnabled)
        }
    }

    public var neonAccent: NeonAccent {
        get {
            guard let raw = defaults.string(forKey: Keys.neonAccent),
                  let accent = NeonAccent(rawValue: raw)
            else {
                return .cyan
            }
            return accent
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.neonAccent)
        }
    }

    public var fontFamily: String {
        get {
            guard let family = defaults.string(forKey: Keys.fontFamily),
                  !family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return "system"
            }
            return family
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(cleaned.isEmpty ? "system" : cleaned, forKey: Keys.fontFamily)
        }
    }

    public var ghostOnUnfocus: Bool {
        get {
            guard defaults.object(forKey: Keys.ghostOnUnfocus) != nil else {
                return false
            }
            return defaults.bool(forKey: Keys.ghostOnUnfocus)
        }
        set {
            defaults.set(newValue, forKey: Keys.ghostOnUnfocus)
        }
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, minOpacity), maxOpacity)
    }

    private static func clampFontSize(_ value: CGFloat) -> CGFloat {
        min(max(value, minFontSize), maxFontSize)
    }
}
