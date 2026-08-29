import Foundation
import Carbon.HIToolbox
import AppKit

// MARK: - Shortcut

/// A configurable shortcut described in JSON as e.g. { "key": "L", "modifiers": ["cmd"] }.
struct Shortcut: Codable, Equatable {
    var key: String
    var modifiers: [String]

    init(key: String, modifiers: [String] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Carbon key code for the `key` string.
    var keyCode: UInt32? {
        Shortcut.keyCodeMap[key.uppercased()]
    }

    /// The set of normalized modifier names (lowercased, canonical).
    private var normalizedModifiers: Set<String> {
        Set(modifiers.map { m -> String in
            switch m.lowercased() {
            case "cmd", "command": return "cmd"
            case "shift": return "shift"
            case "opt", "option", "alt": return "opt"
            case "ctrl", "control": return "ctrl"
            default: return m.lowercased()
            }
        })
    }

    /// True if the given local key event matches this shortcut (key code + exact modifiers).
    func matches(_ event: NSEvent) -> Bool {
        guard let code = keyCode, UInt32(event.keyCode) == code else { return false }
        return normalizedModifiers == Shortcut.eventModifiers(event)
    }

    /// The canonical modifier set present on an event (ignores caps lock / fn / numeric pad).
    static func eventModifiers(_ event: NSEvent) -> Set<String> {
        var set = Set<String>()
        let f = event.modifierFlags
        if f.contains(.command) { set.insert("cmd") }
        if f.contains(.shift)   { set.insert("shift") }
        if f.contains(.option)  { set.insert("opt") }
        if f.contains(.control) { set.insert("ctrl") }
        return set
    }

    /// Carbon modifier mask.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        for m in modifiers.map({ $0.lowercased() }) {
            switch m {
            case "cmd", "command": mask |= UInt32(cmdKey)
            case "shift":          mask |= UInt32(shiftKey)
            case "opt", "option", "alt": mask |= UInt32(optionKey)
            case "ctrl", "control": mask |= UInt32(controlKey)
            default: break
            }
        }
        return mask
    }

    /// Human-readable label like "⌘L".
    var displayLabel: String {
        var parts: [String] = []
        for m in modifiers.map({ $0.lowercased() }) {
            switch m {
            case "cmd", "command": parts.append("⌘")
            case "shift": parts.append("⇧")
            case "opt", "option", "alt": parts.append("⌥")
            case "ctrl", "control": parts.append("⌃")
            default: break
            }
        }
        parts.append(Shortcut.keySymbol(key))
        return parts.joined()
    }

    private static func keySymbol(_ key: String) -> String {
        switch key.uppercased() {
        case "UP": return "↑"
        case "DOWN": return "↓"
        case "LEFT": return "←"
        case "RIGHT": return "→"
        case "RETURN", "ENTER": return "⏎"
        case "ESC", "ESCAPE": return "⎋"
        case "TAB": return "⇥"
        case "SPACE": return "␣"
        case "DELETE", "BACKSPACE": return "⌫"
        default: return key.uppercased()
        }
    }

    static let keyCodeMap: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        // Function keys
        "F1": UInt32(kVK_F1), "F2": UInt32(kVK_F2), "F3": UInt32(kVK_F3),
        "F4": UInt32(kVK_F4), "F5": UInt32(kVK_F5), "F6": UInt32(kVK_F6),
        "F7": UInt32(kVK_F7), "F8": UInt32(kVK_F8), "F9": UInt32(kVK_F9),
        "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12),
        // Arrows
        "UP": UInt32(kVK_UpArrow), "DOWN": UInt32(kVK_DownArrow),
        "LEFT": UInt32(kVK_LeftArrow), "RIGHT": UInt32(kVK_RightArrow),
        // Named keys
        "RETURN": UInt32(kVK_Return), "ENTER": UInt32(kVK_ANSI_KeypadEnter),
        "ESC": UInt32(kVK_Escape), "ESCAPE": UInt32(kVK_Escape),
        "TAB": UInt32(kVK_Tab), "SPACE": UInt32(kVK_Space),
        "DELETE": UInt32(kVK_Delete), "BACKSPACE": UInt32(kVK_Delete),
        "FORWARDDELETE": UInt32(kVK_ForwardDelete),
    ]
}
