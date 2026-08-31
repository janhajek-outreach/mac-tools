import Cocoa

/// Window management tool: move the focused window between displays via global hotkeys.
///
/// Uses the Accessibility API (same permission the copy-paste paste feature already needs)
/// to reposition the frontmost app's window. See `WindowMover` for the geometry.
final class WindowManagerFeature: Feature {
    let id = "window-manager"
    let displayName = "Window Manager"

    private let config: WindowManagerConfig
    private let snapper = WindowSnapper()
    private var nextHotKey: HotKey?
    private var prevHotKey: HotKey?
    private var maximizeHotKey: HotKey?
    private var minimizeHotKey: HotKey?
    private var snapLeftHotKey: HotKey?
    private var snapRightHotKey: HotKey?

    init(config: WindowManagerConfig) {
        self.config = config
    }

    func activate() {
        nextHotKey = HotKey(shortcut: config.nextDisplay, id: 3) {
            WindowMover.moveFocusedWindow(.next)
        }
        prevHotKey = HotKey(shortcut: config.prevDisplay, id: 4) {
            WindowMover.moveFocusedWindow(.previous)
        }
        maximizeHotKey = HotKey(shortcut: config.maximize, id: 5) {
            WindowMover.maximizeFocusedWindow()
        }
        minimizeHotKey = HotKey(shortcut: config.minimize, id: 6) {
            WindowMover.minimizeFocusedWindow()
        }
        snapLeftHotKey = HotKey(shortcut: config.snapLeft, id: 7) { [weak self] in
            self?.snapper.snap(.left)
        }
        snapRightHotKey = HotKey(shortcut: config.snapRight, id: 8) { [weak self] in
            self?.snapper.snap(.right)
        }
        if nextHotKey == nil || prevHotKey == nil || maximizeHotKey == nil
            || minimizeHotKey == nil || snapLeftHotKey == nil || snapRightHotKey == nil {
            NSLog("mac-tools: failed to register window-manager hotkey(s)")
        }
    }

    func menuItems() -> [FeatureMenuItem] {
        [
            FeatureMenuItem(title: "Move Window to Next Display (\(config.nextDisplay.displayLabel))") {
                WindowMover.moveFocusedWindow(.next)
            },
            FeatureMenuItem(title: "Move Window to Previous Display (\(config.prevDisplay.displayLabel))") {
                WindowMover.moveFocusedWindow(.previous)
            },
            FeatureMenuItem(title: "Snap Window Left (\(config.snapLeft.displayLabel))") { [weak self] in
                self?.snapper.snap(.left)
            },
            FeatureMenuItem(title: "Snap Window Right (\(config.snapRight.displayLabel))") { [weak self] in
                self?.snapper.snap(.right)
            },
            FeatureMenuItem(title: "Maximize Window (\(config.maximize.displayLabel))") {
                WindowMover.maximizeFocusedWindow()
            },
            FeatureMenuItem(title: "Minimize Window (\(config.minimize.displayLabel))") {
                WindowMover.minimizeFocusedWindow()
            },
        ]
    }
}
