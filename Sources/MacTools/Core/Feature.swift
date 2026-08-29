import Foundation

/// A single tool within mac-tools (e.g. copy-paste, window management, screenshots).
/// Each feature owns its hotkeys, UI, and data. The app activates all features at launch.
protocol Feature: AnyObject {
    /// Stable identifier, also used as the config sub-directory name.
    var id: String { get }

    /// Human-readable name for the menu bar.
    var displayName: String { get }

    /// Called once at launch to register hotkeys, start monitors, etc.
    func activate()

    /// Optional menu items contributed to the shared status-bar menu.
    func menuItems() -> [FeatureMenuItem]
}

extension Feature {
    func menuItems() -> [FeatureMenuItem] { [] }
}

/// A menu entry contributed by a feature.
struct FeatureMenuItem {
    let title: String
    let action: () -> Void
}
