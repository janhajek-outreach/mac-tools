import Foundation

/// Shared filesystem locations for mac-tools.
///
/// The base directory defaults to `~/.config/mac-tools/` but can be overridden:
///   1. via the `MAC_TOOLS_CONFIG_DIR` environment variable (highest priority), or
///   2. programmatically by assigning `AppPaths.overrideBaseDir` (e.g. from config.json).
/// Supports leading `~` expansion in any supplied path.
enum AppPaths {
    /// Optional runtime override for the base config directory (set from config after load).
    static var overrideBaseDir: URL?

    /// Expand a path that may start with `~`.
    static func expand(_ path: String) -> URL {
        if path.hasPrefix("~") {
            let rest = String(path.dropFirst()).drop(while: { $0 == "/" })
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(rest))
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static var defaultBaseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mac-tools", isDirectory: true)
    }

    static var configDir: URL {
        let base: URL
        if let env = ProcessInfo.processInfo.environment["MAC_TOOLS_CONFIG_DIR"], !env.isEmpty {
            base = expand(env)
        } else if let override = overrideBaseDir {
            base = override
        } else {
            base = defaultBaseDir
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The config file always lives at the (env-resolvable) base dir so it can be found before
    /// the config itself is parsed.
    static var configFile: URL {
        let base: URL
        if let env = ProcessInfo.processInfo.environment["MAC_TOOLS_CONFIG_DIR"], !env.isEmpty {
            base = expand(env)
        } else {
            base = defaultBaseDir
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    /// Per-feature data file, e.g. dataFile("copy-paste", "tabs.json").
    static func dataFile(_ feature: String, _ name: String) -> URL {
        let dir = configDir.appendingPathComponent(feature, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// Resolve a configured path: absolute/`~` paths are used as-is; relative paths are
    /// resolved under the feature's data directory.
    static func resolve(_ path: String, feature: String) -> URL {
        if path.hasPrefix("/") || path.hasPrefix("~") {
            let url = expand(path)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let dir = configDir.appendingPathComponent(feature, isDirectory: true)
            .appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
