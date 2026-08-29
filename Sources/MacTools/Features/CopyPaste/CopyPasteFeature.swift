import Cocoa
import SwiftUI
import Carbon.HIToolbox

/// The copy-paste clipboard manager feature.
final class CopyPasteFeature: Feature {
    let id = "copy-paste"
    let displayName = "Copy Paste"

    private let config: CopyPasteConfig
    private let history: HistoryStore
    private let model: PickerModel

    private var window: NSWindow!
    private var showListHotKey: HotKey?
    private var monitor: ClipboardMonitor!
    private var localKeyMonitor: Any?

    /// The app that was frontmost before we showed our window (to paste back into).
    private var previousApp: NSRunningApplication?

    init(config: CopyPasteConfig) {
        self.config = config
        self.history = HistoryStore(maxHistory: config.maxHistory)
        self.model = PickerModel(history: history)
    }

    func activate() {
        setupModel()
        setupWindow()
        setupClipboardMonitor()
        registerGlobalHotKey()
    }

    func menuItems() -> [FeatureMenuItem] {
        [
            FeatureMenuItem(title: "Show Clipboard (\(config.showList.displayLabel))") { [weak self] in
                self?.showWindow()
            },
            FeatureMenuItem(title: "Clear Clipboard History") { [weak self] in
                self?.history.clear()
            },
        ]
    }

    // MARK: Setup

    private func setupModel() {
        model.onCommit = { [weak self] value in self?.pasteAndHide(value) }
        model.onCancel = { [weak self] in self?.hideWindow() }
    }

    private func setupWindow() {
        let content = NSHostingView(rootView: PanelView(model: model))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipboard"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = content
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
    }

    private func setupClipboardMonitor() {
        monitor = ClipboardMonitor { [weak self] value in
            self?.history.add(value)
        }
        monitor.start()
    }

    private func registerGlobalHotKey() {
        showListHotKey = HotKey(shortcut: config.showList, id: 1) { [weak self] in
            self?.toggleWindow()
        }
        if showListHotKey == nil {
            NSLog("mac-tools: failed to register copy-paste showList hotkey")
        }
    }

    // MARK: Window control

    private func showWindow() {
        previousApp = NSWorkspace.shared.frontmostApplication
        model.reset()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installLocalKeyMonitor()
    }

    private func toggleWindow() {
        if window.isVisible { hideWindow() } else { showWindow() }
    }

    private func hideWindow() {
        removeLocalKeyMonitor()
        window.orderOut(nil)
    }

    private func pasteAndHide(_ value: String) {
        hideWindow()
        Paster.setClipboard(value)
        monitor.syncChangeCount() // don't re-capture our own write

        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.simulatePaste()
        }
    }

    // MARK: Local key handling (only while our window is key)

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKey(event)
        }
    }

    private func removeLocalKeyMonitor() {
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }

    /// Returns nil to swallow the event, or the event to let it propagate (typing in search).
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let code = Int(event.keyCode)
        let cmd = event.modifierFlags.contains(.command)

        if cmd, let searchKey = config.search.keyCode, UInt32(code) == searchKey {
            model.activateSearch()
            return nil
        }

        switch code {
        case kVK_UpArrow:    model.moveUp(); return nil
        case kVK_DownArrow:  model.moveDown(); return nil
        case kVK_Return, kVK_ANSI_KeypadEnter: model.commit(); return nil
        case kVK_Escape:     model.escape(); return nil
        default: return event
        }
    }
}
