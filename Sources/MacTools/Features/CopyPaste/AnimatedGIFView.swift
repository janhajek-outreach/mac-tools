import SwiftUI
import AppKit
import AVFoundation
import CryptoKit
import ImageIO

/// Turns GIFs into small looping video thumbnails (HEVC with alpha, H.264 fallback), cached
/// on disk. Playing a video uses the hardware decoder and keeps only a few frames in memory,
/// whereas holding decoded GIF frames costs width × height × 4 bytes per frame (tens of MB
/// per GIF at tile size).
enum GIFVideoCache {
    /// Longest edge of the video in pixels — enough for a 150pt tile at 2x.
    static let maxPixelSize = 320

    static let dir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.getoutreach.mac-tools/gif-video", isDirectory: true)

    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        return q
    }()
    /// Main-thread only.
    private static var pending: [String: [(URL?) -> Void]] = [:]
    /// Sources that can't be converted (single frame, unreadable) — not retried this run.
    private static var unconvertible = Set<String>()

    /// Calls `completion` on the main thread with the video for `source` (nil if the GIF isn't
    /// animated or can't be converted). Converts in the background on first use.
    static func video(for source: URL, completion: @escaping (URL?) -> Void) {
        guard let out = videoURL(for: source) else { completion(nil); return }
        if FileManager.default.fileExists(atPath: out.path) { completion(out); return }
        let key = out.path
        if unconvertible.contains(key) { completion(nil); return }
        if pending[key] != nil { pending[key]!.append(completion); return }
        pending[key] = [completion]
        queue.addOperation {
            let ok = convert(source, to: out)
            DispatchQueue.main.async {
                if !ok { unconvertible.insert(key) }
                let waiters = pending.removeValue(forKey: key) ?? []
                waiters.forEach { $0(ok ? out : nil) }
            }
        }
    }

    /// `<hash of path>-<hash of size+mtime>-<px>.mov`, so an edited file gets a new video.
    private static func videoURL(for source: URL) -> URL? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: source.path),
              let size = attrs[.size] as? NSNumber,
              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 else { return nil }
        let version = hash("\(size)-\(mtime)").prefix(8)
        return dir.appendingPathComponent("\(pathKey(source))-\(version)-\(maxPixelSize).mov")
    }

    private static func pathKey(_ source: URL) -> String { String(hash(source.path).prefix(16)) }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Delete the videos made from `source` (its blob is being deleted).
    static func remove(_ source: URL) {
        let prefix = pathKey(source) + "-"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    /// Delete videos whose GIF is no longer in any tab (runs in the background).
    static func prune(keeping sources: [URL]) {
        let keep = Set(sources.map(pathKey))
        DispatchQueue.global(qos: .utility).async {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            var removed = 0
            for f in files where !keep.contains(String(f.prefix(16))) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
                removed += 1
            }
            if removed > 0 { NSLog("mac-tools: removed \(removed) unused GIF video(s)") }
        }
    }

    // MARK: Conversion

    private static func convert(_ source: URL, to out: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
        let count = CGImageSourceGetCount(src)
        guard count > 1, let first = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbnailOptions) else { return false }
        // Video dimensions must be even.
        let width = (first.width + 1) & ~1
        let height = (first.height + 1) & ~1

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent("tmp-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let writer = try? AVAssetWriter(outputURL: tmp, fileType: .mov) else { return false }

        // HEVC with alpha keeps GIF transparency; fall back to H.264 (transparent → black).
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.8],
        ]
        var hasAlpha = true
        if !writer.canApply(outputSettings: settings, forMediaType: .video) {
            settings[AVVideoCodecKey] = AVVideoCodecType.h264
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: 1_500_000]
            hasAlpha = false
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        var time = 0.0
        for i in 0..<count {
            guard let frame = i == 0 ? first : CGImageSourceCreateThumbnailAtIndex(src, i, thumbnailOptions) else { continue }
            while !input.isReadyForMoreMediaData { usleep(2_000) }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makeBuffer(pool: pool, frame: frame, width: width, height: height, clear: hasAlpha),
                  adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
            else { writer.cancelWriting(); return false }
            time += delay(src, i)
        }
        input.markAsFinished()
        // The last frame stays up for its own delay.
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { return false }
        return (try? FileManager.default.moveItem(at: tmp, to: out)) != nil
    }

    private static func makeBuffer(pool: CVPixelBufferPool, frame: CGImage, width: Int, height: Int, clear: Bool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if clear { ctx.clear(rect) } else { ctx.setFillColor(.black); ctx.fill(rect) }
        ctx.draw(frame, in: rect)
        return buffer
    }

    private static let thumbnailOptions: CFDictionary = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary

    private static func delay(_ src: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        // Browsers treat very small delays as 0.1s.
        return d < 0.02 ? 0.1 : d
    }
}

/// GIF thumbnail: a still first frame, replaced by the looping video thumbnail while it's
/// `allowed` (window shown + `ui.animateGifs` mode) and actually visible — not merely created
/// by the lazy list/grid ahead of scrolling. When it stops, the player is torn down so only
/// the still image stays in memory.
struct AnimatedGIFView: NSViewRepresentable {
    let source: URL
    let allowed: Bool

    func makeNSView(context: Context) -> GIFVideoView {
        let view = GIFVideoView()
        view.configure(source: source, allowed: allowed)
        return view
    }

    func updateNSView(_ view: GIFVideoView, context: Context) {
        view.configure(source: source, allowed: allowed)
    }

    static func dismantleNSView(_ view: GIFVideoView, coordinator: ()) {
        view.stop()
    }
}

final class GIFVideoView: NSView {
    private(set) var source: URL?
    private var allowed = false
    private var playing = false
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?
    private var readyObservation: NSKeyValueObservation?
    private let playerLayer = AVPlayerLayer()
    private var still: NSImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = .clear
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
        refresh()
    }

    /// Re-check visibility whenever the enclosing scroll view scrolls.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    /// Actually visible: in a window and not clipped away by the scroll view.
    private var isOnScreen: Bool {
        guard window != nil else { return false }
        let visible = visibleRect
        return visible.width > 1 && visible.height > 1
    }

    func configure(source: URL, allowed: Bool) {
        if source != self.source {
            stop()
            self.source = source
            still = BlobStore.thumbnail(at: source, maxPixelSize: GIFVideoCache.maxPixelSize)
            layer?.contents = still
        }
        self.allowed = allowed
        refresh()
    }

    /// Start or stop playback depending on whether it's allowed and visible.
    func refresh() {
        guard let source else { return }
        let want = allowed && isOnScreen
        if want, !playing { start(source) } else if !want, playing { stop() }
    }

    private func start(_ source: URL) {
        playing = true
        GIFVideoCache.video(for: source) { [weak self] video in
            guard let self, self.playing, self.source == source, let video else { return }
            let item = AVPlayerItem(url: video)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.preventsDisplaySleepDuringVideoPlayback = false
            // Loop by seeking back (lighter than AVPlayerLooper, which keeps several item copies).
            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            self.player = player
            self.playerLayer.player = player
            // Swap the still for the video only once a frame is ready (no blank flash, and no
            // still showing through transparent parts of the video).
            self.readyObservation = self.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    guard let self, self.playing else { return }
                    self.playerLayer.isHidden = false
                    self.layer?.contents = nil
                }
            }
            player.play()
        }
    }

    func stop() {
        playing = false
        readyObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        playerLayer.player = nil
        player = nil
        playerLayer.isHidden = true
        layer?.contents = still
    }
}
