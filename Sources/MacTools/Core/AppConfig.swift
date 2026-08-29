import Foundation

/// Top-level app config, persisted to ~/.config/mac-tools/config.json.
/// Each feature has its own nested section. Any missing key falls back to defaults.
struct AppConfig: Codable {
    var app: AppSection
    var copyPaste: CopyPasteConfig
    var screenshot: ScreenshotConfig

    struct AppSection: Codable {
        /// Menu-bar status item title/glyph.
        var menuBarTitle: String
        /// Optional override for the base config directory (absolute or `~`).
        /// The `MAC_TOOLS_CONFIG_DIR` env var, if set, takes precedence over this.
        var configDir: String?
        /// Whether the app should register itself to launch at login on startup.
        var launchAtLogin: Bool

        init(menuBarTitle: String, configDir: String? = nil, launchAtLogin: Bool = false) {
            self.menuBarTitle = menuBarTitle
            self.configDir = configDir
            self.launchAtLogin = launchAtLogin
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = AppConfig.default.app
            menuBarTitle = (try? c.decode(String.self, forKey: .menuBarTitle)) ?? d.menuBarTitle
            configDir = (try? c.decode(String.self, forKey: .configDir)) ?? nil
            launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        }
    }

    init(app: AppSection, copyPaste: CopyPasteConfig, screenshot: ScreenshotConfig) {
        self.app = app
        self.copyPaste = copyPaste
        self.screenshot = screenshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = (try? c.decode(AppSection.self, forKey: .app)) ?? AppConfig.default.app
        copyPaste = (try? c.decode(CopyPasteConfig.self, forKey: .copyPaste)) ?? AppConfig.default.copyPaste
        screenshot = (try? c.decode(ScreenshotConfig.self, forKey: .screenshot)) ?? AppConfig.default.screenshot
    }

    static let `default` = AppConfig(
        app: AppSection(menuBarTitle: "🧰", configDir: nil, launchAtLogin: false),
        copyPaste: .default,
        screenshot: .default
    )
}

enum AppConfigStore {
    static func load() -> AppConfig {
        let url = AppPaths.configFile
        guard let data = try? Data(contentsOf: url) else {
            save(.default)
            return .default
        }
        do {
            let cfg = try JSONDecoder().decode(AppConfig.self, from: data)
            // Apply a config-dir override (env var still wins inside AppPaths).
            if let dir = cfg.app.configDir, !dir.isEmpty {
                AppPaths.overrideBaseDir = AppPaths.expand(dir)
            }
            return cfg
        } catch {
            NSLog("mac-tools: failed to parse config.json (\(error)); using defaults")
            return .default
        }
    }

    static func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: AppPaths.configFile)
        }
    }
}
