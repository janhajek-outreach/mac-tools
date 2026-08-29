import Foundation
import Carbon.HIToolbox

// MARK: - Shortcut

/// A configurable shortcut described in JSON as e.g. { "key": "L", "modifiers": ["cmd"] }.
struct Shortcut: Codable, Equatable {
    var key: String
    var modifiers: [String]

    /// Carbon key code for the `key` character.
    var keyCode: UInt32? {
        Shortcut.keyCodeMap[key.uppercased()]
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
        parts.append(key.uppercased())
        return parts.joined()
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
    ]
}
