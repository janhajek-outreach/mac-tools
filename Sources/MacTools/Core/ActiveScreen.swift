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
        return current(holding: focusedWindow(of: target))
    }

    /// Same as `current(preferring:)` but for an already-resolved AX window, so callers that
    /// captured the window earlier don't pay for a second Accessibility round-trip.
    static func current(holding window: AXUIElement?) -> NSScreen? {
        if let window, let f = frame(of: window), let screen = screen(containingCG: f) {
            return screen
        }
        if let screen = screenUnderMouse() { return screen }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Centers `rect`'s size within the active screen's visible area (AppKit bottom-left space).
    static func centeredFrame(size: CGSize, preferring app: NSRunningApplication? = nil) -> NSRect? {
        centeredFrame(size: size, on: current(preferring: app))
    }

    /// Centers `size` on the screen holding `window` (falling back to mouse/main screen).
    static func centeredFrame(size: CGSize, holding window: AXUIElement?) -> NSRect? {
        centeredFrame(size: size, on: current(holding: window))
    }

    private static func centeredFrame(size: CGSize, on screen: NSScreen?) -> NSRect? {
        guard let screen else { return nil }
        let vis = screen.visibleFrame
        return NSRect(
            x: vis.midX - size.width / 2,
            y: vis.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The app's currently focused window, or nil without Accessibility permission.
    ///
    /// Callers can hold on to this element to later raise *that one window* instead of
    /// activating the whole app (which would drag its windows on other displays forward too).
    static func focusedWindow(of app: NSRunningApplication?) -> AXUIElement? {
        guard let app = app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw = raw else { return nil }
        // Force-cast is safe: the focused-window attribute is always an AXUIElement.
        return (raw as! AXUIElement)
    }

    /// Frame of an AX window in CG (top-left origin) space.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = axValue(window, kAXPositionAttribute, .cgPoint, as: CGPoint.self),
              let size = axValue(window, kAXSizeAttribute, .cgSize, as: CGSize.self) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Helpers

    /// Frame of the app's focused window in CG (top-left origin) space.
    private static func focusedWindowFrame(of app: NSRunningApplication?) -> CGRect? {
        focusedWindow(of: app).flatMap(frame(of:))
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
