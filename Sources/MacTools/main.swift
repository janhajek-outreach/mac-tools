import Cocoa

/// mac-tools: a single menu-bar app hosting multiple macOS utilities.
/// Add new tools by implementing `Feature` and appending to `buildFeatures()`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let config = AppConfigStore.load()
    private var features: [Feature] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        features = buildFeatures()
        features.forEach { $0.activate() }

        setupStatusItem()

        // Some features (paste) need Accessibility; prompt once up front.
        Paster.ensureAccessibilityPermission(prompt: true)
    }

    private func buildFeatures() -> [Feature] {
        [
            CopyPasteFeature(config: config.copyPaste),
            // Future: WindowManagerFeature(...), ScreenshotFeature(...), AltTabFeature(...)
        ]
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🧰"

        let menu = NSMenu()
        for feature in features {
            let items = feature.menuItems()
            guard !items.isEmpty else { continue }
            for item in items {
                let mi = NSMenuItem(title: item.title, action: #selector(runAction(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.action
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(title: "Quit mac-tools", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
