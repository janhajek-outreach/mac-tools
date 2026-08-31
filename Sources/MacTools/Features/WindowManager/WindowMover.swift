import Cocoa
import ApplicationServices
import MacToolsGeometry

/// Moves the frontmost app's focused window between displays using the Accessibility API.
///
/// Coordinate note: AppKit (`NSScreen`) uses a bottom-left origin, while the AX API and
/// CoreGraphics use a top-left origin. All geometry here is normalized to the CG top-left
/// space via `cgFrame(_:)` / `cgVisibleFrame(_:)`, and only converted at the edges.
/// The pure math lives in `MacToolsGeometry.WindowGeometry` (unit-tested).
enum WindowMover {
    enum Direction { case next, previous }

    // MARK: - Debug logging

    /// Appends to a file (unified logging wasn't reliably capturing NSLog here).
    /// Tail it with:  tail -f /tmp/mac-tools-wm.log
    private static let logURL = URL(fileURLWithPath: "/tmp/mac-tools-wm.log")
    private static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        NSLog("mac-tools WM: \(message)")
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: logURL) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
    private static func rectStr(_ r: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", r.minX, r.minY, r.width, r.height)
    }

    /// Records the last placement so rapid, successive moves chain deterministically instead
    /// of re-reading a stale AX position (which caused displays to be skipped).
    private struct MoveState {
        let window: AXUIElement
        let index: Int          // screen index (into `orderedScreens()`)
        let rect: CGRect        // CG top-left frame we placed the window at
        let time: TimeInterval
    }
    private static var lastMove: MoveState?
    /// How long a recorded placement stays authoritative for chained moves.
    private static let moveChainTimeout: TimeInterval = 0.8

    /// Move the focused window to the next / previous display, scaling it proportionally to
    /// the target screen's visible area (and keeping it maximized if it was).
    static func moveFocusedWindow(_ direction: Direction) {
        let dir = direction == .next ? "next" : "prev"
        let trusted = AXIsProcessTrusted()
        let screens = orderedScreens()
        log("move(\(dir)) trusted=\(trusted) screens=\(screens.count) "
            + "visFrames=[\(screens.map { rectStr(cgVisibleFrame($0)) }.joined(separator: ", "))]")

        guard screens.count > 1 else {
            log("move(\(dir)) ABORT: only \(screens.count) screen(s)")
            NSSound.beep()  // nothing to move to
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            log("move(\(dir)) ABORT: no frontmost app")
            NSSound.beep()
            return
        }
        guard let window = focusedWindow() else {
            log("move(\(dir)) ABORT: no focused window (frontApp=\(app.localizedName ?? "?") pid=\(app.processIdentifier))")
            NSSound.beep()
            return
        }
        log("move(\(dir)) frontApp=\(app.localizedName ?? "?") pid=\(app.processIdentifier)")

        // Determine the window's current screen & frame. During fast successive presses the
        // AX position read lags the previous move; if we just moved this same window, trust
        // the recorded state so we advance exactly one display at a time.
        let now = ProcessInfo.processInfo.systemUptime
        let live = windowFrame(window)
        log("move(\(dir)) liveFrame=\(live.map { rectStr($0) } ?? "nil") "
            + "liveIdx=\(live.map { String(screenIndex(containing: $0, in: screens)) } ?? "?") "
            + "cache=\(lastMove.map { "idx=\($0.index) rect=\(rectStr($0.rect)) age=\(String(format: "%.2f", now - $0.time))s same=\(CFEqual($0.window, window))" } ?? "none")")

        let current: (index: Int, frame: CGRect)
        if let last = lastMove, CFEqual(last.window, window),
           now - last.time < moveChainTimeout, screens.indices.contains(last.index) {
            current = (last.index, last.rect)
            log("move(\(dir)) source=CACHE curIdx=\(current.index) curFrame=\(rectStr(current.frame))")
        } else if let frame = live {
            current = (screenIndex(containing: frame, in: screens), frame)
            log("move(\(dir)) source=GEOMETRY curIdx=\(current.index) curFrame=\(rectStr(current.frame))")
        } else {
            log("move(\(dir)) ABORT: could not read window frame")
            NSSound.beep()
            return
        }

        let delta = direction == .next ? 1 : -1
        let targetIndex = (current.index + delta + screens.count) % screens.count
        guard targetIndex != current.index else {
            log("move(\(dir)) NO-OP: target==current (\(targetIndex))")
            return
        }

        let curVis = cgVisibleFrame(screens[current.index])
        let tgtVis = cgVisibleFrame(screens[targetIndex])
        let maxed = isMaximized(current.frame, in: curVis)
        // If the window fills its current display, keep it maximized on the target display
        // (fill the new visible area) instead of scaling.
        let target = maxed ? tgtVis : mappedFrame(window: current.frame, from: curVis, to: tgtVis)
        log("move(\(dir)) \(current.index)->\(targetIndex) maximized=\(maxed) "
            + "curVis=\(rectStr(curVis)) tgtVis=\(rectStr(tgtVis)) target=\(rectStr(target))")

        setWindowFrame(window, target)
        lastMove = MoveState(window: window, index: targetIndex, rect: target, time: now)

        if let after = windowFrame(window) {
            log("move(\(dir)) DONE readback=\(rectStr(after)) "
                + "matches=\(abs(after.minX - target.minX) < 5 && abs(after.width - target.width) < 5)")
        } else {
            log("move(\(dir)) DONE readback=nil")
        }
    }

    /// Maximize the focused window: fill the visible area of the display it's currently on.
    static func maximizeFocusedWindow() {
        log("maximize trusted=\(AXIsProcessTrusted())")
        guard let window = focusedWindow(), let frame = windowFrame(window) else {
            log("maximize ABORT: no focused window / frame")
            NSSound.beep()
            return
        }
        let screens = orderedScreens()
        let index = screenIndex(containing: frame, in: screens)
        let vis = cgVisibleFrame(screens[index])
        log("maximize idx=\(index) from=\(rectStr(frame)) to=\(rectStr(vis))")
        setWindowFrame(window, vis)
        // Record so a following rapid move treats it as maximized on this display.
        lastMove = MoveState(window: window, index: index, rect: vis,
                             time: ProcessInfo.processInfo.systemUptime)
        if let after = windowFrame(window) { log("maximize DONE readback=\(rectStr(after))") }
    }

    /// Minimize the focused window to the Dock.
    static func minimizeFocusedWindow() {
        log("minimize trusted=\(AXIsProcessTrusted())")
        guard let window = focusedWindow() else {
            log("minimize ABORT: no focused window")
            NSSound.beep()
            return
        }
        let err = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        log("minimize setMinimized err=\(err.rawValue)")
        lastMove = nil
    }

    // MARK: - Half snapping

    enum Side { case left, right }

    /// A candidate window that could fill the empty half after a snap.
    struct Candidate {
        let window: AXUIElement
        let pid: pid_t
        let appName: String
        let title: String
        let icon: NSImage?
    }

    /// Context returned after snapping, describing the now-empty half to offer for filling.
    struct GapContext {
        let emptyRect: CGRect        // CG top-left space
        let excluded: AXUIElement    // the window we just snapped (don't offer it)
    }

    /// Snap the focused window to the left/right half of its current display.
    /// Returns the empty-half context so the caller can offer other windows to fill it,
    /// or nil if there was nothing to snap.
    @discardableResult
    static func snapFocusedWindow(_ side: Side) -> GapContext? {
        guard let window = focusedWindow(), let frame = windowFrame(window) else {
            NSSound.beep()
            return nil
        }
        let screens = orderedScreens()
        let vis = cgVisibleFrame(screens[screenIndex(containing: frame, in: screens)])
        let (left, right) = halves(of: vis)
        let placed = side == .left ? left : right
        setWindowFrame(window, placed)
        lastMove = MoveState(window: window, index: screenIndex(containing: frame, in: screens),
                             rect: placed, time: ProcessInfo.processInfo.systemUptime)
        return GapContext(emptyRect: side == .left ? right : left, excluded: window)
    }

    /// Left/right halves of a visible area (CG top-left space).
    private static func halves(of vis: CGRect) -> (left: CGRect, right: CGRect) {
        WindowGeometry.halves(of: vis)
    }

    /// Visible windows of other regular apps, excluding a given window and minimized ones.
    static func candidateWindows(excluding excluded: AXUIElement) -> [Candidate] {
        var result: [Candidate] = []
        let me = getpid()
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != me {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for w in windows {
                if CFEqual(w, excluded) { continue }
                if boolAttr(w, kAXMinimizedAttribute) == true { continue }
                guard let f = windowFrame(w), f.width > 80, f.height > 80 else { continue }
                let title = stringAttr(w, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 }
                    ?? app.localizedName ?? "Window"
                result.append(Candidate(
                    window: w, pid: app.processIdentifier,
                    appName: app.localizedName ?? "", title: title, icon: app.icon
                ))
            }
        }
        return result
    }

    /// Place a specific window into a rect and bring it to the front.
    static func placeAndRaise(_ window: AXUIElement, in rect: CGRect, pid: pid_t) {
        setWindowFrame(window, rect)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    }

    /// Convert the center of a CG (top-left) rect to an AppKit screen point (bottom-left).
    static func nsScreenPoint(forCGCenterOf rect: CGRect) -> CGPoint {
        let top = primaryScreen?.frame.maxY ?? rect.maxY
        return CGPoint(x: rect.midX, y: top - rect.midY)
    }

    // MARK: - Accessibility

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value)
        guard err == .success, let element = value else {
            log("focusedWindow: copyFocusedWindow err=\(err.rawValue) (pid=\(app.processIdentifier))")
            return nil
        }
        // Force-cast is safe: the focused-window attribute is always an AXUIElement.
        return (element as! AXUIElement)
    }

    private static func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let pos = axValue(window, kAXPositionAttribute, .cgPoint, as: CGPoint.self),
              let size = axValue(window, kAXSizeAttribute, .cgSize, as: CGSize.self) else {
            return nil
        }
        return CGRect(origin: pos, size: size)
    }

    private static func setWindowFrame(_ window: AXUIElement, _ rect: CGRect) {
        let before = windowFrame(window)
        let growing = before.map { rect.width > $0.width + 2 || rect.height > $0.height + 2 } ?? false

        // Many apps enable AXEnhancedUserInterface, which *animates* AX-driven moves/resizes —
        // that animation is what flashes the small window on the new display before it grows.
        // Disable it around the frame change so position+size apply as one instant step.
        withEnhancedUIDisabled(for: window) {
            applyFrame(window, rect, growing: growing, pass: 1)
        }

        // Safety net: if a stubborn app still didn't land (rare), re-apply once it has settled
        // on the new display a tick later.
        guard let after = windowFrame(window) else { return }
        let landed = abs(after.minX - rect.minX) < 6 && abs(after.minY - rect.minY) < 6
            && abs(after.width - rect.width) < 6 && abs(after.height - rect.height) < 6
        if landed { return }
        log("setWindowFrame pass1 mismatch after=\(rectStr(after)) growing=\(growing) — scheduling pass2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withEnhancedUIDisabled(for: window) {
                applyFrame(window, rect, growing: growing, pass: 2)
            }
            if let a2 = windowFrame(window) { log("setWindowFrame pass2 readback=\(rectStr(a2))") }
        }
    }

    /// Temporarily turn off the owning app's `AXEnhancedUserInterface` (if on) so AX geometry
    /// changes apply instantly instead of animating. Restores the previous value afterwards.
    private static func withEnhancedUIDisabled(for window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { body(); return }
        let app = AXUIElementCreateApplication(pid)
        let attr = "AXEnhancedUserInterface" as CFString
        let wasEnabled = boolAttr(app, "AXEnhancedUserInterface") == true
        if wasEnabled {
            AXUIElementSetAttributeValue(app, attr, kCFBooleanFalse)
        }
        body()
        if wasEnabled {
            AXUIElementSetAttributeValue(app, attr, kCFBooleanTrue)
        }
    }

    /// Apply a frame. Order depends on grow vs shrink so a single pass lands cleanly:
    ///  - growing: position → size → position (resize on the target/bigger display)
    ///  - shrinking: size → position → size (shrink before/while moving)
    private static func applyFrame(_ window: AXUIElement, _ rect: CGRect, growing: Bool, pass: Int) {
        let errs: [Int32]
        if growing {
            errs = [setPosition(window, rect.origin), setSize(window, rect.size), setPosition(window, rect.origin)]
        } else {
            errs = [setSize(window, rect.size), setPosition(window, rect.origin), setSize(window, rect.size)]
        }
        log("applyFrame(pass\(pass) \(growing ? "grow" : "shrink")) \(rectStr(rect)) errs=\(errs)")
    }

    @discardableResult
    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> Int32 {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return -999 }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value).rawValue
    }

    @discardableResult
    private static func setSize(_ window: AXUIElement, _ size: CGSize) -> Int32 {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return -999 }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value).rawValue
    }

    /// Read an AXValue attribute and unwrap it into a concrete geometry type.
    private static func axValue<T>(_ element: AXUIElement, _ attr: String,
                                   _ type: AXValueType, as _: T.Type) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success,
              let raw = raw else { return nil }
        let axValue = raw as! AXValue
        let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        guard AXValueGetValue(axValue, type, out) else { return nil }
        return out.pointee
    }

    /// Read a boolean AX attribute (e.g. `kAXMinimizedAttribute`).
    private static func boolAttr(_ element: AXUIElement, _ attr: String) -> Bool? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success,
              let raw = raw, CFGetTypeID(raw) == CFBooleanGetTypeID() else { return nil }
        return (raw as! CFBoolean) == kCFBooleanTrue
    }

    /// Read a string AX attribute (e.g. `kAXTitleAttribute`).
    private static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    // MARK: - Geometry (bridges NSScreen → pure WindowGeometry in CG top-left space)

    /// The primary display (origin at the global 0,0) defines the coordinate reference.
    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
    }

    /// Convert an NSScreen's full frame (bottom-left origin) to CG top-left origin.
    private static func cgFrame(_ screen: NSScreen) -> CGRect {
        WindowGeometry.flipToCG(screen.frame, primaryTop: primaryScreen?.frame.maxY ?? screen.frame.maxY)
    }

    /// Convert an NSScreen's visible frame (excludes menu bar / Dock) to CG top-left origin.
    private static func cgVisibleFrame(_ screen: NSScreen) -> CGRect {
        WindowGeometry.flipToCG(screen.visibleFrame, primaryTop: primaryScreen?.frame.maxY ?? screen.visibleFrame.maxY)
    }

    /// Screens ordered left→right, then top→bottom, so "next/previous" is intuitive.
    private static func orderedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        return WindowGeometry.orderedIndices(of: screens.map(cgFrame)).map { screens[$0] }
    }

    /// Index of the screen the window overlaps most; falls back to the one under its center.
    private static func screenIndex(containing frame: CGRect, in screens: [NSScreen]) -> Int {
        WindowGeometry.screenIndex(containing: frame, in: screens.map(cgFrame))
    }

    private static func isMaximized(_ frame: CGRect, in vis: CGRect) -> Bool {
        WindowGeometry.isMaximized(frame, in: vis)
    }

    private static func mappedFrame(window: CGRect, from src: CGRect, to dst: CGRect) -> CGRect {
        WindowGeometry.mappedFrame(window: window, from: src, to: dst)
    }
}
