import Foundation
import ServiceManagement

/// Wraps macOS login-item registration via SMAppService (macOS 13+).
/// Lets the app launch itself at login without a separate helper target.
enum LoginItem {
    /// True if the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register (enable) or unregister (disable) launch-at-login.
    /// Returns true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("mac-tools: failed to \(enabled ? "enable" : "disable") login item (\(error))")
            return false
        }
    }

    /// Flip the current state.
    @discardableResult
    static func toggle() -> Bool {
        setEnabled(!isEnabled)
    }
}
