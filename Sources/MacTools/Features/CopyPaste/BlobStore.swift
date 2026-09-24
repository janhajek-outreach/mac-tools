import Foundation
import AppKit
import ImageIO

/// A directory holding image/file bytes ("blobs") under generated `<UUID>.<ext>` names.
struct BlobDir {
    let dir: URL

    init(_ dir: URL) {
        self.dir = dir
    }

    /// Creates the directory on demand so a wiped cache folder heals itself.
    private func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func url(for filename: String) -> URL {
        dir.appendingPathComponent(filename)
    }

    /// Write bytes with the given extension; returns the generated filename.
    @discardableResult
    func write(_ data: Data, ext: String) -> String? {
        ensureDir()
        let filename = "\(UUID().uuidString).\(ext)"
        do {
            try data.write(to: url(for: filename))
            return filename
        } catch {
            NSLog("mac-tools: failed to write blob (\(error))")
            return nil
        }
    }

    func exists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    func delete(_ filename: String) {
        let fileURL = url(for: filename)
        BlobStore.evict(fileURL)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Copy a file in without loading it into memory (APFS clones it when source and
    /// destination share a volume). Returns the generated blob filename.
    func copyFile(from source: URL) -> String? {
        ensureDir()
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: source, to: url(for: filename))
            return filename
        } catch {
            NSLog("mac-tools: failed to copy file into blob store (\(error))")
            return nil
        }
    }

    /// Move a file in (e.g. a finished download) under a generated name with `ext`.
    func moveFile(from source: URL, ext: String) -> String? {
        ensureDir()
        let filename = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.moveItem(at: source, to: url(for: filename))
            return filename
        } catch {
            NSLog("mac-tools: failed to move file into blob store (\(error))")
            return nil
        }
    }

    /// Filenames currently in the directory (hidden files excluded).
    func allFilenames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { !$0.hasPrefix(".") } ?? []
    }
}

/// The two blob directories — one for the Clipboard tab (volatile history, defaults to
/// Caches) and one for snippet tabs (kept, defaults to Application Support) — plus shared
/// thumbnail helpers. Directories are set at startup via `configure`.
enum BlobStore {
    // Placeholders until `configure` runs at startup (no directories are created here).
    private(set) static var clipboard = BlobDir(AppPaths.configDir.appendingPathComponent("copy-paste/blobs"))
    private(set) static var snippets = BlobDir(AppPaths.configDir.appendingPathComponent("copy-paste/blobs"))

    static func configure(clipboard clipboardDir: URL, snippets snippetDir: URL) {
        clipboard = BlobDir(clipboardDir)
        snippets = BlobDir(snippetDir)
    }

    private static let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 100
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    /// Drop in-memory thumbnails/frames for a file that's being deleted.
    static func evict(_ fileURL: URL) {
        for px in thumbnailSizes { imageCache.removeObject(forKey: "\(fileURL.path)@\(px)" as NSString) }
        GIFVideoCache.remove(fileURL)
    }

    /// Pixel sizes thumbnails have been made at (so `evict` can find every cached variant).
    private static var thumbnailSizes = Set<Int>()

    /// Downscaled thumbnail (default 160px, i.e. 80pt at 2x) for an image file — a blob or a
    /// linked original. Cached in memory per size so redraws don't re-read the file.
    static func thumbnail(at fileURL: URL, maxPixelSize: Int = 160) -> NSImage? {
        let key = "\(fileURL.path)@\(maxPixelSize)" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnailSizes.insert(maxPixelSize)
        imageCache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }

    static func isGIF(_ fileURL: URL) -> Bool {
        fileURL.pathExtension.lowercased() == "gif"
    }
}
