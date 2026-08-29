import Cocoa

/// Polls the general pasteboard for changes and reports new string values.
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let onNewValue: (String) -> Void

    init(onNewValue: @escaping (String) -> Void) {
        self.onNewValue = onNewValue
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

        if let str = pb.string(forType: .string), !str.isEmpty {
            onNewValue(str)
        }
    }
}
