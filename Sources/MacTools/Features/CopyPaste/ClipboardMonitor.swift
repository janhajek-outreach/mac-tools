import Cocoa

/// Polls the general pasteboard for changes and reports new items (text, image, or file).
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let onNewItem: (ClipItem) -> Void

    init(onNewItem: @escaping (ClipItem) -> Void) {
        self.onNewItem = onNewItem
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start(interval: TimeInterval = 0.3) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ignore the next change we cause ourselves (e.g. when we set the pasteboard to paste).
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let item = Self.readItem(from: pb) {
            onNewItem(item)
        }
    }

    /// Files larger than this are linked (bookmark) instead of copied into the blob store.
    static var fileCopyLimitBytes: Int64 = 30 * 1024 * 1024

    /// Read the richest representation available. Priority: file URL > image > text.
    static func readItem(from pb: NSPasteboard) -> ClipItem? {
        // 1. File(s) — take the first file URL.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, url.isFileURL {
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
            let kind: ClipItemKind = isImageExt(ext) ? .image : .file
            if let size = FileReference.size(of: url), size > fileCopyLimitBytes,
               let bookmark = FileReference.bookmark(for: url) {
                return ClipItem(kind: kind, originalName: url.lastPathComponent, bookmark: bookmark)
            }
            if let data = try? Data(contentsOf: url) {
                // If it's an image file, keep it as an image so we get a thumbnail.
                if NSImage(data: data) != nil, isImageExt(ext) {
                    if let blob = BlobStore.clipboard.write(data, ext: ext) {
                        return ClipItem(kind: .image, blobFilename: blob, originalName: url.lastPathComponent)
                    }
                }
                if let blob = BlobStore.clipboard.write(data, ext: ext) {
                    return ClipItem(kind: .file, blobFilename: blob, originalName: url.lastPathComponent)
                }
            }
        }

        // 2. Image data on the pasteboard (e.g. screenshot). GIF first so animation survives.
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        if let data = pb.data(forType: gifType), NSImage(data: data) != nil,
           let blob = BlobStore.clipboard.write(data, ext: "gif") {
            return ClipItem(kind: .image, blobFilename: blob, originalName: imageName(from: pb, ext: "gif"))
        }
        if let (data, ext) = pngImageData(from: pb),
           let blob = BlobStore.clipboard.write(data, ext: ext) {
            return ClipItem(kind: .image, blobFilename: blob, originalName: imageName(from: pb, ext: ext))
        }

        // 3. Plain text.
        if let str = pb.string(forType: .string), !str.isEmpty {
            return ClipItem(kind: .text, text: str)
        }

        return nil
    }

    /// Image bytes stored as PNG: taken as-is when offered (screenshots, browsers), otherwise
    /// converted from TIFF (uncompressed, typically 5-10x larger). Falls back to raw TIFF if
    /// the conversion fails.
    private static func pngImageData(from pb: NSPasteboard) -> (Data, String)? {
        if let png = pb.data(forType: .png), NSImage(data: png) != nil {
            return (png, "png")
        }
        guard let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        if let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return (tiff, "tiff")
    }

    /// Display name for pasted image data. Browsers (Chrome, Firefox, Slack…) include the
    /// source `<img src="…">` as HTML — use its file name, with the extension of the bytes we
    /// actually store. Falls back to `clipboard.<ext>`.
    static func imageName(from pb: NSPasteboard, ext: String) -> String {
        let fallback = "clipboard.\(ext)"
        guard let html = pb.string(forType: .html),
              let src = firstImageSource(in: html),
              let url = URL(string: src), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.lastPathComponent != "/" else { return fallback }
        let base = (url.lastPathComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return fallback }
        return "\(String(base.prefix(120))).\(ext)"
    }

    private static func firstImageSource(in html: String) -> String? {
        let pattern = #"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func isImageExt(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"].contains(ext.lowercased())
    }
}
