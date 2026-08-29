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

    /// Read the richest representation available. Priority: file URL > image > text.
    static func readItem(from pb: NSPasteboard) -> ClipItem? {
        // 1. File(s) — take the first file URL.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, url.isFileURL {
            if let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
                // If it's an image file, keep it as an image so we get a thumbnail.
                if NSImage(data: data) != nil, isImageExt(ext) {
                    if let blob = BlobStore.write(data, ext: ext) {
                        return ClipItem(kind: .image, blobFilename: blob, originalName: url.lastPathComponent)
                    }
                }
                if let blob = BlobStore.write(data, ext: ext) {
                    return ClipItem(kind: .file, blobFilename: blob, originalName: url.lastPathComponent)
                }
            }
        }

        // 2. Image data on the pasteboard (e.g. screenshot).
        if let imgType = pb.availableType(from: [.tiff, .png]),
           let data = pb.data(forType: imgType),
           NSImage(data: data) != nil {
            let ext = (imgType == .png) ? "png" : "tiff"
            if let blob = BlobStore.write(data, ext: ext) {
                return ClipItem(kind: .image, blobFilename: blob, originalName: "clipboard.\(ext)")
            }
        }

        // 3. Plain text.
        if let str = pb.string(forType: .string), !str.isEmpty {
            return ClipItem(kind: .text, text: str)
        }

        return nil
    }

    private static func isImageExt(_ ext: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp"].contains(ext.lowercased())
    }
}
