import Cocoa
import Carbon.HIToolbox

/// Writes a value to the pasteboard and simulates Cmd+V into the frontmost app.
enum Paster {
    /// Put `value` on the clipboard.
    static func setClipboard(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }

    /// Simulate a Cmd+V keystroke. Requires Accessibility permission.
    static func simulatePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let vKey = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Returns true if Accessibility permission is granted (needed to post key events).
    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
