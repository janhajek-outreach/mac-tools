import Cocoa
import Carbon.HIToolbox

/// Writes items to the pasteboard and simulates Cmd+V into the frontmost app.
enum Paster {
    /// Put an item's content on the clipboard. `fileURL` is where an image/file item's bytes
    /// live — its blob, or the resolved original for a linked item. The caller resolves it
    /// first so it can refuse items whose file is missing.
    static func setClipboard(_ item: ClipItem, fileURL: URL? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if item.isReference {
            if let url = fileURL { pb.writeObjects([pasteURL(forLinked: url, name: item.originalName) as NSURL]) }
            return
        }

        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)

        case .image:
            if let blob = item.blobFilename, let fileURL, let data = try? Data(contentsOf: fileURL) {
                let ext = (blob as NSString).pathExtension.lowercased()
                switch ext {
                case "png":
                    pb.setData(data, forType: .png)
                case "tiff", "tif":
                    pb.setData(data, forType: .tiff)
                default:
                    // GIF/JPEG/WebP/HEIC: paste as a file so apps get the original bytes
                    // (keeps GIF animation), plus raw + TIFF data for image-only targets.
                    let tmp = materialize(data, name: item.originalName, blob: blob, ext: ext)
                    let pbItem = NSPasteboardItem()
                    if let tmp { pbItem.setString(tmp.absoluteString, forType: .fileURL) }
                    if ext == "gif" {
                        pbItem.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
                    }
                    if let tiff = NSImage(data: data)?.tiffRepresentation {
                        pbItem.setData(tiff, forType: .tiff)
                    }
                    pb.writeObjects([pbItem])
                }
            }

        case .file:
            if let blob = item.blobFilename, let fileURL {
                // Stage a copy under the item's name (APFS clone — instant) and paste its URL.
                let name = (item.originalName?.isEmpty == false ? item.originalName! : blob)
                    .replacingOccurrences(of: "/", with: "-")
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: tmp)
                if (try? FileManager.default.copyItem(at: fileURL, to: tmp)) != nil {
                    pb.writeObjects([tmp as NSURL])
                }
            }
        }
    }

    /// A linked original is pasted as-is, like Finder does. If the item was renamed (F2),
    /// paste a temp copy under the new name instead — `copyItem` clones on APFS, so this is
    /// instant and takes no extra space even for huge files.
    private static func pasteURL(forLinked url: URL, name: String?) -> URL {
        guard let name, !name.isEmpty, name != url.lastPathComponent else { return url }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-tools-paste", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dest = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            NSLog("mac-tools: failed to stage renamed file for paste (\(error))")
            return url
        }
    }

    /// Write blob bytes to a temp file named after the item, ensuring the right extension.
    private static func materialize(_ data: Data, name: String?, blob: String, ext: String) -> URL? {
        var filename = (name?.isEmpty == false) ? name! : blob
        if (filename as NSString).pathExtension.lowercased() != ext {
            filename += ".\(ext)"
        }
        filename = filename.replacingOccurrences(of: "/", with: "-")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tmp)
            return tmp
        } catch {
            NSLog("mac-tools: failed to write temp image (\(error))")
            return nil
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
