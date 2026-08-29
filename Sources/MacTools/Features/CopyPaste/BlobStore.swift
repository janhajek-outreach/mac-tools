import Foundation
import AppKit

/// Stores image/file bytes on disk. The directory is configurable and set at startup
/// via `BlobStore.configure(dir:)`; defaults to the copy-paste feature's `blobs/` dir.
enum BlobStore {
    private static var overrideDir: URL?

    /// Point the blob store at a configured directory (absolute, `~`, or relative to the
    /// feature data dir — resolution handled by the caller).
    static func configure(dir: URL) {
        overrideDir = dir
    }

    static var dir: URL {
        let url = overrideDir ?? AppPaths.dataFile("copy-paste", "blobs")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for filename: String) -> URL {
        dir.appendingPathComponent(filename)
    }

    /// Write bytes with the given extension; returns the generated filename.
    @discardableResult
    static func write(_ data: Data, ext: String) -> String? {
        let filename = "\(UUID().uuidString).\(ext)"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            NSLog("mac-tools: failed to write blob (\(error))")
            return nil
        }
    }

    static func read(_ filename: String) -> Data? {
        try? Data(contentsOf: url(for: filename))
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    /// Load an NSImage for an image blob (used for thumbnails).
    static func image(_ filename: String) -> NSImage? {
        guard let data = read(filename) else { return nil }
        return NSImage(data: data)
    }
}
