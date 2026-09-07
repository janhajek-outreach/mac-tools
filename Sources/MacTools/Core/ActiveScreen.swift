import Cocoa
import ApplicationServices
import MacToolsGeometry

/// Figures out which display the user is currently working on, so panels can be shown there
/// instead of always on the primary display.
///
/// Resolution order:
///  1. The focused window of the given (or frontmost) app — the most accurate signal.
///  2. The display under the mouse pointer.
///  3. `NSScreen.main`, then the first screen.
enum ActiveScreen {
    /// The screen the user currently has focus on, or nil if there are no screens.
    static func current(preferring app: NSRunningApplication? = nil) -> NSScreen? {
        let target = app ?? NSWorkspace.shared.frontmostApplication
        if let frame = focusedWindowFrame(of: target), let screen = screen(containingCG: frame) {
            return screen
        }
        if let screen = screenUnderMouse() { return screen }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Centers `rect`'s size within the active screen's visible area (AppKit bottom-left space).
    static func centeredFrame(size: CGSize, preferring app: NSRunningApplication? = nil) -> NSRect? {
        guard let screen = current(preferring: app) else { return nil }
        let vis = screen.visibleFrame
        return NSRect(
            x: vis.midX - size.width / 2,
            y: vis.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Helpers

    /// Frame of the app's focused window in CG (top-left origin) space.
    private static func focusedWindowFrame(of app: NSRunningApplication?) -> CGRect? {
        guard let app = app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw = raw else { return nil }
        let window = raw as! AXUIElement
        guard let origin = axValue(window, kAXPositionAttribute, .cgPoint, as: CGPoint.self),
              let size = axValue(window, kAXSizeAttribute, .cgSize, as: CGSize.self) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func screen(containingCG frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let top = primaryTop(of: screens)
        let cgFrames = screens.map { WindowGeometry.flipToCG($0.frame, primaryTop: top) }
        let index = WindowGeometry.screenIndex(containing: frame, in: cgFrames)
        return screens.indices.contains(index) ? screens[index] : nil
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation   // AppKit bottom-left global space
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private static func primaryTop(of screens: [NSScreen]) -> CGFloat {
        (screens.first { $0.frame.origin == .zero } ?? screens[0]).frame.maxY
    }

    private static func axValue<T>(_ element: AXUIElement, _ attr: String,
                                   _ type: AXValueType, as _: T.Type) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success,
              let raw = raw else { return nil }
        let value = raw as! AXValue
        let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        guard AXValueGetValue(value, type, out) else { return nil }
        return out.pointee
    }
}
