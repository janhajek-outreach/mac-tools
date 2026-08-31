import Foundation

/// Settings for the window-manager tool. Fully JSON-configurable; missing keys fall back
/// to defaults.
struct WindowManagerConfig: Codable {
    /// Global hotkey: move the focused window to the next display (left→right order).
    var nextDisplay: Shortcut
    /// Global hotkey: move the focused window to the previous display.
    var prevDisplay: Shortcut
    /// Global hotkey: maximize the focused window (fill the current display).
    var maximize: Shortcut
    /// Global hotkey: minimize the focused window to the Dock.
    var minimize: Shortcut
    /// Global hotkey: snap the focused window to the left half of the current display.
    var snapLeft: Shortcut
    /// Global hotkey: snap the focused window to the right half of the current display.
    var snapRight: Shortcut

    init(nextDisplay: Shortcut, prevDisplay: Shortcut, maximize: Shortcut, minimize: Shortcut,
         snapLeft: Shortcut, snapRight: Shortcut) {
        self.nextDisplay = nextDisplay
        self.prevDisplay = prevDisplay
        self.maximize = maximize
        self.minimize = minimize
        self.snapLeft = snapLeft
        self.snapRight = snapRight
    }

    // Per-field fallback: any missing key uses the default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WindowManagerConfig.default
        nextDisplay = (try? c.decode(Shortcut.self, forKey: .nextDisplay)) ?? d.nextDisplay
        prevDisplay = (try? c.decode(Shortcut.self, forKey: .prevDisplay)) ?? d.prevDisplay
        maximize = (try? c.decode(Shortcut.self, forKey: .maximize)) ?? d.maximize
        minimize = (try? c.decode(Shortcut.self, forKey: .minimize)) ?? d.minimize
        snapLeft = (try? c.decode(Shortcut.self, forKey: .snapLeft)) ?? d.snapLeft
        snapRight = (try? c.decode(Shortcut.self, forKey: .snapRight)) ?? d.snapRight
    }

    static let `default` = WindowManagerConfig(
        nextDisplay: Shortcut(key: "RIGHT", modifiers: ["ctrl", "opt"]),
        prevDisplay: Shortcut(key: "LEFT", modifiers: ["ctrl", "opt"]),
        maximize: Shortcut(key: "UP", modifiers: ["ctrl", "opt"]),
        minimize: Shortcut(key: "DOWN", modifiers: ["ctrl", "opt"]),
        snapLeft: Shortcut(key: "LEFT", modifiers: ["ctrl", "opt", "cmd"]),
        snapRight: Shortcut(key: "RIGHT", modifiers: ["ctrl", "opt", "cmd"])
    )
}
