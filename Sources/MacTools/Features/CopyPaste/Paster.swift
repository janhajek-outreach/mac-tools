import Cocoa
import Carbon.HIToolbox

/// Writes items to the pasteboard and simulates Cmd+V into the frontmost app.
enum Paster {
    /// Put an item's content on the clipboard.
    static func setClipboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)

        case .image:
            if let blob = item.blobFilename, let data = BlobStore.read(blob) {
                let type: NSPasteboard.PasteboardType =
                    (blob as NSString).pathExtension.lowercased() == "png" ? .png : .tiff
                pb.setData(data, forType: type)
            }

        case .file:
            if let blob = item.blobFilename, let data = BlobStore.read(blob) {
                // Materialize into a temp file and put its URL on the pasteboard.
                let name = item.originalName ?? blob
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? data.write(to: tmp)
                pb.writeObjects([tmp as NSURL])
            }
        }
    }

    /// Put raw text on the clipboard (used for multi-item paste).
    static func setPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Simulate a Cmd+V keystroke. Requires Accessibility permission.
    static func simulatePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        let tap: CGEventTapLocation = .cgSessionEventTap
        keyDown?.post(tap: tap)
        keyUp?.post(tap: tap)
    }

    /// Returns true if Accessibility permission is granted (needed to post key events).
    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Show a one-time-ish alert explaining that paste needs Accessibility.
    static func warnAccessibilityMissing() {
        // Trigger the system prompt too.
        _ = ensureAccessibilityPermission(prompt: true)

        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = """
        mac-tools copied the item to your clipboard, but it can't auto-paste until you \
        grant Accessibility access.

        Open System Settings → Privacy & Security → Accessibility and enable MacTools, \
        then try again. (You can paste manually with ⌘V for now.)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
