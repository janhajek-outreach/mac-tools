import Foundation

/// Settings for the screenshot tool. Fully JSON-configurable; missing keys fall back to defaults.
struct ScreenshotConfig: Codable {
    /// Global hotkey that starts an interactive rectangle capture.
    var capture: Shortcut
    /// Absolute path to the capture executable.
    var command: String
    /// Arguments passed to the capture executable.
    /// Defaults to `-i` (interactive rectangle) + `-c` (copy to clipboard).
    var arguments: [String]

    init(capture: Shortcut, command: String, arguments: [String]) {
        self.capture = capture
        self.command = command
        self.arguments = arguments
    }

    // Per-field fallback: any missing key uses the default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScreenshotConfig.default
        capture = (try? c.decode(Shortcut.self, forKey: .capture)) ?? d.capture
        command = (try? c.decode(String.self, forKey: .command)) ?? d.command
        arguments = (try? c.decode([String].self, forKey: .arguments)) ?? d.arguments
    }

    static let `default` = ScreenshotConfig(
        capture: Shortcut(key: "F12", modifiers: ["opt"]),
        command: "/usr/sbin/screencapture",
        arguments: ["-i", "-c"]
    )
}
