import Foundation

/// Helpers for "linked" items: files too large to copy into the blob store, kept as a
/// Finder-alias-style bookmark that survives moves/renames on the same volume.
enum FileReference {
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolve a bookmark to an existing file. Returns nil when the file is gone, the volume
    /// isn't mounted, or the file sits in the Trash (we treat trashed files as deleted).
    /// `refreshed` is a new bookmark when the stored one is stale (file moved/renamed).
    static func resolve(_ bookmark: Data) -> (url: URL, refreshed: Data?)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path),
              !url.pathComponents.contains(".Trash") else { return nil }
        return (url, stale ? self.bookmark(for: url) : nil)
    }

    static func size(of url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true, let size = values?.fileSize else { return nil }
        return Int64(size)
    }

    /// Free space on the volume holding `url` (what the system considers available for
    /// important, user-initiated work — includes purgeable space).
    static func freeSpace(at url: URL) -> Int64? {
        // The target folder may not exist yet; measure the nearest existing ancestor.
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
