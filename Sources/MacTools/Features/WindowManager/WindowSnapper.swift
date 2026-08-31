import Cocoa

/// Snaps the focused window to a display half, then offers other visible windows to fill
/// the empty half via a native popup menu (snap-assist).
final class WindowSnapper: NSObject {
    private var candidates: [WindowMover.Candidate] = []
    private var targetRect: CGRect = .zero

    /// Snap the focused window to `side`, then pop up a menu of windows to fill the gap.
    func snap(_ side: WindowMover.Side) {
        guard let gap = WindowMover.snapFocusedWindow(side) else { return }
        offerGapFill(gap)
    }

    private func offerGapFill(_ gap: WindowMover.GapContext) {
        let items = WindowMover.candidateWindows(excluding: gap.excluded)
        guard !items.isEmpty else { return }   // nothing to offer; leave the gap empty
        candidates = items
        targetRect = gap.emptyRect

        let menu = NSMenu()
        menu.title = "Fill the gap"
        for (i, c) in items.enumerated() {
            let title = c.appName.isEmpty ? c.title : "\(c.appName) — \(c.title)"
            let mi = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            if let icon = c.icon {
                let img = icon.copy() as! NSImage
                img.size = NSSize(width: 16, height: 16)
                mi.image = img
            }
            menu.addItem(mi)
        }

        NSApp.activate(ignoringOtherApps: true)
        let point = WindowMover.nsScreenPoint(forCGCenterOf: gap.emptyRect)
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard candidates.indices.contains(sender.tag) else { return }
        let c = candidates[sender.tag]
        WindowMover.placeAndRaise(c.window, in: targetRect, pid: c.pid)
        candidates = []
    }
}
