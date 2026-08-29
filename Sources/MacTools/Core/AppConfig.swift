import Foundation

/// Top-level app config, persisted to ~/.config/mac-tools/config.json.
/// Each feature has its own nested section.
struct AppConfig: Codable {
    var copyPaste: CopyPasteConfig

    static let `default` = AppConfig(
        copyPaste: .default
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
            return try JSONDecoder().decode(AppConfig.self, from: data)
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
