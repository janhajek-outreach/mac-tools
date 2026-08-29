import Foundation

/// Shared filesystem locations for mac-tools. Config lives under ~/.config/mac-tools/.
enum AppPaths {
    static var configDir: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mac-tools", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var configFile: URL { configDir.appendingPathComponent("config.json") }

    /// Per-feature data file, e.g. dataFile("copy-paste", "history.json").
    static func dataFile(_ feature: String, _ name: String) -> URL {
        let dir = configDir.appendingPathComponent(feature, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
