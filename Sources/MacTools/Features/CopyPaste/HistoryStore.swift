import Foundation
import Combine

/// Persistent, observable clipboard history. Newest entry is at index 0.
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [String] = []

    private let maxHistory: Int
    private let fileURL = AppPaths.dataFile("copy-paste", "history.json")

    init(maxHistory: Int) {
        self.maxHistory = maxHistory
        load()
    }

    /// Add a newly-copied value to the top. If it already exists, move it to the top.
    func add(_ value: String) {
        guard !value.isEmpty else { return }

        if let existing = items.firstIndex(of: value) {
            items.remove(at: existing)
        }
        items.insert(value, at: 0)

        if items.count > maxHistory {
            items.removeLast(items.count - maxHistory)
        }
        save()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        items = Array(decoded.prefix(maxHistory))
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL)
        }
    }
}
