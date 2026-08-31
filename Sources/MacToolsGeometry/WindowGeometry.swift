import CoreGraphics

/// Pure window/display geometry used by the window manager. Everything here operates on
/// plain `CGRect`s in the CoreGraphics **top-left** origin coordinate space, with no
/// dependency on `NSScreen`/AppKit or the Accessibility API — so it is fully unit-testable.
///
/// AppKit uses a bottom-left origin; callers convert `NSScreen` frames with `flipToCG`
/// before handing them here.
public enum WindowGeometry {

    /// Convert an AppKit (bottom-left origin) rect to CG top-left origin.
    /// - Parameter primaryTop: the top edge of the primary display in AppKit coords
    ///   (i.e. the primary screen's `frame.maxY`), which defines the global flip axis.
    public static func flipToCG(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Order display indices left→right, then top→bottom. Returns the original indices in
    /// display order, so callers can map back to their own screen array.
    public static func orderedIndices(of frames: [CGRect]) -> [Int] {
        frames.indices.sorted { a, b in
            frames[a].minX != frames[b].minX
                ? frames[a].minX < frames[b].minX
                : frames[a].minY < frames[b].minY
        }
    }

    /// Index of the display a window sits on: the one it overlaps most, falling back to the
    /// display under the window's center, then to `0`.
    public static func screenIndex(containing frame: CGRect, in frames: [CGRect]) -> Int {
        var bestIndex = 0
        var bestArea: CGFloat = -1
        for (i, f) in frames.enumerated() {
            let inter = f.intersection(frame)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea { bestArea = area; bestIndex = i }
        }
        if bestArea > 0 { return bestIndex }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for (i, f) in frames.enumerated() where f.contains(center) { return i }
        return bestIndex
    }

    /// Left/right halves of a visible area.
    public static func halves(of vis: CGRect) -> (left: CGRect, right: CGRect) {
        let w = (vis.width / 2).rounded()
        let left = CGRect(x: vis.minX, y: vis.minY, width: w, height: vis.height)
        let right = CGRect(x: vis.minX + w, y: vis.minY, width: vis.width - w, height: vis.height)
        return (left, right)
    }

    /// True when the window essentially fills the given visible area (i.e. it's maximized).
    /// A few points of tolerance absorbs app-specific insets and rounding.
    public static func isMaximized(_ frame: CGRect, in vis: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(frame.minX - vis.minX) <= tolerance &&
        abs(frame.minY - vis.minY) <= tolerance &&
        abs(frame.width - vis.width) <= tolerance &&
        abs(frame.height - vis.height) <= tolerance
    }

    /// Map a window from one display's visible area onto another, **scaling proportionally**
    /// so it keeps the same relative position and footprint on the target display. The result
    /// is clamped to sit fully within the destination.
    public static func mappedFrame(window: CGRect, from src: CGRect, to dst: CGRect) -> CGRect {
        guard src.width > 0, src.height > 0 else { return window }

        let relX = (window.minX - src.minX) / src.width
        let relY = (window.minY - src.minY) / src.height
        let relW = window.width  / src.width
        let relH = window.height / src.height

        var size = CGSize(width: relW * dst.width, height: relH * dst.height)
        size.width  = min(size.width,  dst.width)
        size.height = min(size.height, dst.height)

        var origin = CGPoint(x: dst.minX + relX * dst.width,
                             y: dst.minY + relY * dst.height)
        origin.x = min(max(origin.x, dst.minX), dst.maxX - size.width)
        origin.y = min(max(origin.y, dst.minY), dst.maxY - size.height)

        return CGRect(origin: origin, size: size)
    }
}
