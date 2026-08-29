import Cocoa

/// Interactive rectangle screenshot tool.
///
/// On the configured hotkey, launches macOS's native crosshair selection
/// (`screencapture -i -c`), which writes the captured PNG to the clipboard.
/// The copy-paste feature's ClipboardMonitor then auto-captures it into the
/// Clipboard tab with a thumbnail — no extra wiring needed here.
final class ScreenshotFeature: Feature {
    let id = "screenshot"
    let displayName = "Screenshot"

    private let config: ScreenshotConfig
    private var captureHotKey: HotKey?

    init(config: ScreenshotConfig) {
        self.config = config
    }

    func activate() {
        captureHotKey = HotKey(shortcut: config.capture, id: 2) { [weak self] in
            self?.captureInteractive()
        }
        if captureHotKey == nil {
            NSLog("mac-tools: failed to register screenshot capture hotkey")
        }
    }

    func menuItems() -> [FeatureMenuItem] {
        [
            FeatureMenuItem(title: "Capture Screenshot (\(config.capture.displayLabel))") { [weak self] in
                self?.captureInteractive()
            },
        ]
    }

    // MARK: Capture

    /// Run the configured capture command. Defaults to `screencapture -i -c`
    /// (`-i` = interactive rectangle selection, `-c` = copy result to the clipboard).
    private func captureInteractive() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.command)
        proc.arguments = config.arguments
        do {
            try proc.run()
        } catch {
            NSLog("mac-tools: failed to launch '\(config.command)' (\(error))")
            warnScreenRecordingMaybeMissing()
        }
    }

    /// Screen capture requires Screen Recording permission on modern macOS.
    /// If capture ever comes back empty repeatedly, the user likely needs to grant it.
    private func warnScreenRecordingMaybeMissing() {
        let alert = NSAlert()
        alert.messageText = "Couldn't start screenshot"
        alert.informativeText = """
        mac-tools couldn't launch the screen capture tool. If screenshots come out blank, \
        grant Screen Recording under System Settings → Privacy & Security → Screen Recording, \
        then try again.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
