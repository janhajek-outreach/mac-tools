import SwiftUI
import AppKit
import ImageIO
import QuartzCore

/// Pre-decoded, downscaled frames of an animated GIF.
final class GIFFrames {
    let frames: [CGImage]
    /// Cumulative key times in 0...1 for `CAKeyframeAnimation`.
    let keyTimes: [NSNumber]
    let duration: Double
    let cost: Int

    init(frames: [CGImage], delays: [Double]) {
        self.frames = frames
        let total = delays.reduce(0, +)
        self.duration = total
        var acc = 0.0
        var times: [NSNumber] = []
        for d in delays {
            times.append(NSNumber(value: total > 0 ? acc / total : 0))
            acc += d
        }
        self.keyTimes = times
        self.cost = frames.reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }
}

/// Decodes GIF files into small frame sequences once, off the main thread, and caches them
/// (keyed by file path). Playback is then done by Core Animation, so animating costs almost
/// no CPU in-process (unlike NSImageView, which re-decompresses the full-size GIF every frame).
enum GIFFrameCache {
    /// 80pt thumbnail at 2x.
    static let maxPixelSize = 160

    private static let cache: NSCache<NSString, GIFFrames> = {
        let c = NSCache<NSString, GIFFrames>()
        c.countLimit = 100
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()
    private static let queue = DispatchQueue(label: "mac-tools.gif-decode", qos: .utility)
    private static var pending: [String: [(GIFFrames?) -> Void]] = [:]
    /// Pixel sizes frames have been decoded at (so `remove` can find every cached variant).
    private static var sizes = Set<Int>()

    private static func key(_ url: URL, _ px: Int) -> String { "\(url.path)@\(px)" }

    static func cached(_ url: URL, maxPixelSize px: Int = maxPixelSize) -> GIFFrames? {
        cache.object(forKey: key(url, px) as NSString)
    }

    static func remove(_ url: URL) {
        for px in sizes { cache.removeObject(forKey: key(url, px) as NSString) }
    }

    /// Calls `completion` on the main thread with the decoded frames (nil if undecodable).
    static func load(_ url: URL, maxPixelSize px: Int = maxPixelSize, completion: @escaping (GIFFrames?) -> Void) {
        if let hit = cached(url, maxPixelSize: px) { completion(hit); return }
        let key = key(url, px)
        if pending[key] != nil { pending[key]!.append(completion); return }
        pending[key] = [completion]
        sizes.insert(px)
        queue.async {
            let frames = decode(url, maxPixelSize: px)
            DispatchQueue.main.async {
                if let frames { cache.setObject(frames, forKey: key as NSString, cost: frames.cost) }
                let waiters = pending.removeValue(forKey: key) ?? []
                waiters.forEach { $0(frames) }
            }
        }
    }

    private static func decode(_ url: URL, maxPixelSize px: Int) -> GIFFrames? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        var frames: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<count {
            guard let img = CGImageSourceCreateThumbnailAtIndex(src, i, thumbnailOptions(px)) else { continue }
            frames.append(img)
            delays.append(delay(src, i))
        }
        return frames.isEmpty ? nil : GIFFrames(frames: frames, delays: delays)
    }

    private static func thumbnailOptions(_ px: Int) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: px,
        ] as CFDictionary
    }

    /// Small first frame, decoded synchronously — shown while the full sequence decodes.
    static func firstFrame(_ url: URL, maxPixelSize px: Int = maxPixelSize) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbnailOptions(px))
    }

    private static func delay(_ src: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        // Browsers treat very small delays as 0.1s.
        return d < 0.02 ? 0.1 : d
    }
}

/// Tracks which GIF rows are currently on screen and pokes their views directly, so scroll
/// visibility changes don't re-render the SwiftUI list.
enum GIFVisibility {
    private(set) static var onScreen = Set<String>()
    private static let views = NSHashTable<GIFLayerView>.weakObjects()

    static func register(_ view: GIFLayerView) { views.add(view) }

    static func set(_ url: URL, onScreen visible: Bool) {
        let key = url.path
        if visible { onScreen.insert(key) } else { onScreen.remove(key) }
        for view in views.allObjects where view.source?.path == key { view.refresh() }
    }
}

/// GIF thumbnail rendered by a Core Animation keyframe animation. Shows a static first frame
/// until all frames are decoded, and whenever it isn't animating. It animates only when
/// `allowed` (window shown + `ui.animateGifs` mode) and its row is on screen.
struct AnimatedGIFView: NSViewRepresentable {
    let source: URL
    var maxPixelSize: Int = GIFFrameCache.maxPixelSize
    let allowed: Bool

    func makeNSView(context: Context) -> GIFLayerView {
        let view = GIFLayerView()
        GIFVisibility.register(view)
        view.configure(source: source, maxPixelSize: maxPixelSize, allowed: allowed)
        return view
    }

    func updateNSView(_ view: GIFLayerView, context: Context) {
        view.configure(source: source, maxPixelSize: maxPixelSize, allowed: allowed)
    }
}

final class GIFLayerView: NSView {
    private static let animationKey = "gif"
    private(set) var source: URL?
    private var maxPixelSize = GIFFrameCache.maxPixelSize
    private var frames: GIFFrames?
    private var allowed = false
    private var animating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    func configure(source: URL, maxPixelSize: Int, allowed: Bool) {
        if source != self.source || maxPixelSize != self.maxPixelSize {
            self.source = source
            self.maxPixelSize = maxPixelSize
            frames = GIFFrameCache.cached(source, maxPixelSize: maxPixelSize)
            animating = false
            layer?.removeAnimation(forKey: Self.animationKey)
            layer?.contents = frames?.frames.first ?? GIFFrameCache.firstFrame(source, maxPixelSize: maxPixelSize)
        }
        self.allowed = allowed
        refresh()
    }

    /// Recompute whether to animate; decodes frames lazily the first time they're needed.
    func refresh() {
        guard let source else { return }
        let want = allowed && GIFVisibility.onScreen.contains(source.path)
        if want, frames == nil {
            let px = maxPixelSize
            GIFFrameCache.load(source, maxPixelSize: px) { [weak self] loaded in
                guard let self, self.source == source, self.maxPixelSize == px, let loaded else { return }
                self.frames = loaded
                self.refresh()
            }
            return
        }
        guard want != animating else { return }
        animating = want
        applyAnimation()
    }

    private func applyAnimation() {
        guard let layer else { return }
        layer.removeAnimation(forKey: Self.animationKey)
        guard animating, let frames, frames.frames.count > 1, frames.duration > 0 else { return }
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = frames.frames
        anim.keyTimes = frames.keyTimes
        anim.calculationMode = .discrete
        anim.duration = frames.duration
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: Self.animationKey)
    }
}
