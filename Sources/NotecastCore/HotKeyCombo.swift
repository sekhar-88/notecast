import AppKit
import Carbon.HIToolbox

/// Represents a global keyboard shortcut backed by Carbon virtual key codes and modifier masks.
public struct HotKeyCombo: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & HotKeyCombo.supportedCarbonModifierMask
    }

    /// Default global hotkey: `⌥ Space`.
    public static let defaultToggle = HotKeyCombo(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey)
    )

    private static let supportedCarbonModifierMask: UInt32 =
        UInt32(cmdKey | optionKey | controlKey | shiftKey)

    private static let modifierOnlyKeyCodes: Set<Int> = [
        kVK_Command,
        kVK_RightCommand,
        kVK_Shift,
        kVK_RightShift,
        kVK_Option,
        kVK_RightOption,
        kVK_Control,
        kVK_RightControl,
        kVK_CapsLock,
        kVK_Function
    ]

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19
    ]

    /// Validates a keyCode + Cocoa modifier flags into a bindable global shortcut.
    /// Rejects modifier-only keys, Escape, and non-function keys lacking `⌘`, `⌥`, or `⌃`.
    public static func from(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> HotKeyCombo? {
        let code = Int(keyCode)
        if modifierOnlyKeyCodes.contains(code) || code == kVK_Escape {
            return nil
        }

        let carbonMods = carbonModifiers(from: modifierFlags)
        let primaryMask = UInt32(cmdKey | optionKey | controlKey)
        let hasPrimaryModifier = (carbonMods & primaryMask) != 0

        if !hasPrimaryModifier && !functionKeyCodes.contains(code) {
            return nil
        }

        return HotKeyCombo(keyCode: UInt32(keyCode), carbonModifiers: carbonMods)
    }

    /// Converts Cocoa `NSEvent.ModifierFlags` to Carbon modifier flags.
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Human-readable macOS shortcut label (e.g. `"⌥ Space"`, `"⌘⇧N"`).
    public var displayString: String {
        var prefix = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { prefix += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { prefix += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { prefix += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { prefix += "⌘" }

        let key = keyLabel(for: Int(keyCode))
        if !prefix.isEmpty && key == "Space" {
            return "\(prefix) \(key)"
        }
        return "\(prefix)\(key)"
    }

    private func keyLabel(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0, kVK_ANSI_Keypad0: return "0"
        case kVK_ANSI_1, kVK_ANSI_Keypad1: return "1"
        case kVK_ANSI_2, kVK_ANSI_Keypad2: return "2"
        case kVK_ANSI_3, kVK_ANSI_Keypad3: return "3"
        case kVK_ANSI_4, kVK_ANSI_Keypad4: return "4"
        case kVK_ANSI_5, kVK_ANSI_Keypad5: return "5"
        case kVK_ANSI_6, kVK_ANSI_Keypad6: return "6"
        case kVK_ANSI_7, kVK_ANSI_Keypad7: return "7"
        case kVK_ANSI_8, kVK_ANSI_Keypad8: return "8"
        case kVK_ANSI_9, kVK_ANSI_Keypad9: return "9"
        case kVK_ANSI_Equal, kVK_ANSI_KeypadEquals: return "="
        case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash, kVK_ANSI_KeypadDivide: return "/"
        case kVK_ANSI_Period, kVK_ANSI_KeypadDecimal: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_KeypadPlus: return "+"
        case kVK_ANSI_KeypadMultiply: return "*"
        default: return "Key\(keyCode)"
        }
    }
}
