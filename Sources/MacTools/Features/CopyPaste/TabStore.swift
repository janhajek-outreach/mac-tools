import Foundation
import Combine

/// A named collection of items. Tab 0 is the auto-capture "Clipboard" tab.
struct ClipTab: Codable, Identifiable {
    var id: UUID
    var name: String
    var items: [ClipItem]

    init(id: UUID = UUID(), name: String, items: [ClipItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// Owns all tabs and their persistence.
final class TabStore: ObservableObject {
    @Published private(set) var tabs: [ClipTab]
    @Published var currentTab: Int = 0

    private let maxHistory: Int
    private let tabsURL: URL
    private let clipboardURL: URL

    /// Index of the auto-capture tab.
    let clipboardTabIndex = 0

    init(
        maxHistory: Int,
        snippetTabNames: [String],
        clipboardTabName: String = "Clipboard",
        tabsFileURL: URL? = nil,
        clipboardFileURL: URL? = nil
    ) {
        self.maxHistory = maxHistory
        let tabsU = tabsFileURL ?? AppPaths.dataFile("copy-paste", "tabs.json")
        let clipU = clipboardFileURL ?? AppPaths.dataFile("copy-paste", "clipboard.json")
        self.tabsURL = tabsU
        self.clipboardURL = clipU

        // Load the tab structure (custom tabs + names; clipboard tab present but item-less).
        var loadedTabs: [ClipTab]
        if let loaded = TabStore.loadTabs(from: tabsU), !loaded.isEmpty {
            loadedTabs = loaded
        } else {
            loadedTabs = [ClipTab(name: clipboardTabName)]
            loadedTabs.append(contentsOf: snippetTabNames.map { ClipTab(name: $0) })
        }
        // Merge the volatile clipboard items into the clipboard tab.
        let clipboardFileExists = FileManager.default.fileExists(atPath: clipU.path)
        if let clipItems = TabStore.loadClipboardItems(from: clipU),
           loadedTabs.indices.contains(0) {
            loadedTabs[0].items = clipItems
        }
        self.tabs = loadedTabs

        // One-time migration: older tabs.json embedded clipboard items in tab 0. If there's no
        // separate clipboard.json yet but tab 0 has items, split them out now so tabs.json becomes
        // clean/sync-friendly and clipboard items live in their own file.
        if !clipboardFileExists,
           self.tabs.indices.contains(clipboardTabIndex),
           !self.tabs[clipboardTabIndex].items.isEmpty {
            saveClipboard()
            saveTabs()
        }
    }

    // MARK: Derived

    var currentItems: [ClipItem] {
        guard tabs.indices.contains(currentTab) else { return [] }
        return tabs[currentTab].items
    }

    var tabNames: [String] { tabs.map(\.name) }

    /// A one-line summary of what is currently at the top of the clipboard (auto-capture) tab —
    /// i.e. the most recent thing copied. Empty string if there's nothing yet.
    var currentClipboardSummary: String {
        guard tabs.indices.contains(clipboardTabIndex),
              let item = tabs[clipboardTabIndex].items.first else { return "" }
        switch item.kind {
        case .text:
            return (item.text ?? "").replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
        case .image: return item.originalName ?? "Image"
        case .file:  return item.originalName ?? "File"
        }
    }

    // MARK: Tab navigation

    func nextTab() { if !tabs.isEmpty { currentTab = (currentTab + 1) % tabs.count } }
    func prevTab() { if !tabs.isEmpty { currentTab = (currentTab - 1 + tabs.count) % tabs.count } }

    // MARK: Tab management

    /// Add a new tab and switch to it. Returns its index.
    @discardableResult
    func addTab(name: String = "New Tab") -> Int {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs.append(ClipTab(name: trimmed.isEmpty ? "New Tab" : trimmed))
        currentTab = tabs.count - 1
        saveTabs()
        return currentTab
    }

    /// Remove a tab. The auto-capture Clipboard tab (index 0) cannot be removed.
    func removeTab(at index: Int) {
        guard tabs.indices.contains(index), index != clipboardTabIndex, tabs.count > 1 else { return }
        // Free any blobs unique to this tab.
        let removedItems = tabs[index].items
        for item in removedItems {
            let others = tabs.enumerated().filter { $0.offset != index }.flatMap { $0.element.items }
            freeBlobIfUnreferenced(item, excluding: others)
        }
        tabs.remove(at: index)
        if currentTab >= tabs.count { currentTab = tabs.count - 1 }
        saveTabs()
    }

    /// Rename a tab. The Clipboard tab can be renamed too.
    func renameTab(at index: Int, to name: String) {
        guard tabs.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tabs[index].name = trimmed
        saveTabs()
    }

    // MARK: Auto-capture (clipboard tab only)

    func capture(_ item: ClipItem) {
        var items = tabs[clipboardTabIndex].items
        // De-dup: remove an existing item with the same content.
        if let idx = items.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
            // Free its blob if it was an image/file we're about to replace.
            freeBlobIfUnreferenced(items[idx], excluding: items)
            items.remove(at: idx)
        }
        items.insert(item, at: 0)
        if items.count > maxHistory {
            for removed in items[maxHistory...] {
                freeBlobIfUnreferenced(removed, excluding: allItems())
            }
            items.removeLast(items.count - maxHistory)
        }
        tabs[clipboardTabIndex].items = items
        saveClipboard()
    }

    // MARK: Item operations (operate on current tab unless noted)

    func delete(_ id: UUID, in tabIndex: Int) {
        guard tabs.indices.contains(tabIndex),
              let idx = tabs[tabIndex].items.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs[tabIndex].items.remove(at: idx)
        freeBlobIfUnreferenced(removed, excluding: allItems())
        save(affectedTab: tabIndex)
    }

    func setLabel(_ label: String?, for id: UUID, in tabIndex: Int) {
        mutate(id, in: tabIndex) { $0.label = (label?.isEmpty == true) ? nil : label }
    }

    func setText(_ text: String, for id: UUID, in tabIndex: Int) {
        mutate(id, in: tabIndex) { item in
            guard item.kind == .text else { return }
            item.text = text
        }
    }

    /// Move an item up/down within its tab.
    func move(_ id: UUID, in tabIndex: Int, by delta: Int) {
        guard tabs.indices.contains(tabIndex),
              let idx = tabs[tabIndex].items.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard tabs[tabIndex].items.indices.contains(target) else { return }
        tabs[tabIndex].items.swapAt(idx, target)
        save(affectedTab: tabIndex)
    }

    /// Copy an item into another tab (F5). Blob is duplicated so tabs are independent.
    func copyItem(_ id: UUID, from sourceTab: Int, to destTab: Int) {
        guard tabs.indices.contains(sourceTab), tabs.indices.contains(destTab), sourceTab != destTab,
              let item = tabs[sourceTab].items.first(where: { $0.id == id }) else { return }

        var copy = item
        copy.id = UUID()
        if let blob = item.blobFilename, let data = BlobStore.read(blob) {
            let ext = (blob as NSString).pathExtension
            copy.blobFilename = BlobStore.write(data, ext: ext)
        }
        tabs[destTab].items.insert(copy, at: 0)
        save(affectedTab: destTab)
    }

    // MARK: Multi-item operations

    /// Delete many items (by id) from a tab.
    func delete(_ ids: [UUID], in tabIndex: Int) {
        guard tabs.indices.contains(tabIndex) else { return }
        let idSet = Set(ids)
        let removed = tabs[tabIndex].items.filter { idSet.contains($0.id) }
        tabs[tabIndex].items.removeAll { idSet.contains($0.id) }
        for item in removed { freeBlobIfUnreferenced(item, excluding: allItems()) }
        save(affectedTab: tabIndex)
    }

    /// Copy many items to another tab, preserving order (top-most first).
    func copyItems(_ ids: [UUID], from sourceTab: Int, to destTab: Int) {
        guard tabs.indices.contains(sourceTab), tabs.indices.contains(destTab), sourceTab != destTab else { return }
        // Insert in reverse so the first id ends up on top.
        for id in ids.reversed() { copyItem(id, from: sourceTab, to: destTab) }
    }

    /// Move a contiguous or scattered set of items up/down as a block within a tab.
    func moveMany(_ ids: [UUID], in tabIndex: Int, by delta: Int) {
        guard delta != 0, tabs.indices.contains(tabIndex) else { return }
        var items = tabs[tabIndex].items
        let idSet = Set(ids)
        // Indices of selected items, in list order.
        let indices = items.indices.filter { idSet.contains(items[$0].id) }
        guard !indices.isEmpty else { return }

        if delta < 0 {
            // Move up: process top-to-bottom.
            for idx in indices {
                let target = idx - 1
                guard target >= 0, !idSet.contains(items[target].id) else { continue }
                items.swapAt(idx, target)
            }
        } else {
            // Move down: process bottom-to-top.
            for idx in indices.reversed() {
                let target = idx + 1
                guard target < items.count, !idSet.contains(items[target].id) else { continue }
                items.swapAt(idx, target)
            }
        }
        tabs[tabIndex].items = items
        save(affectedTab: tabIndex)
    }

    // MARK: Helpers

    private func mutate(_ id: UUID, in tabIndex: Int, _ change: (inout ClipItem) -> Void) {
        guard tabs.indices.contains(tabIndex),
              let idx = tabs[tabIndex].items.firstIndex(where: { $0.id == id }) else { return }
        change(&tabs[tabIndex].items[idx])
        save(affectedTab: tabIndex)
    }

    private func allItems() -> [ClipItem] { tabs.flatMap(\.items) }

    private func freeBlobIfUnreferenced(_ item: ClipItem, excluding others: [ClipItem]) {
        guard let blob = item.blobFilename else { return }
        let stillUsed = others.contains { $0.id != item.id && $0.blobFilename == blob }
        if !stillUsed { BlobStore.delete(blob) }
    }

    // MARK: Persistence

    /// A stable encoder: sorted keys + pretty printing so a one-field change produces a
    /// minimal, deterministic diff (no field-order churn).
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Load the tab structure. The clipboard tab (index 0) is stored WITHOUT its items here.
    private static func loadTabs(from url: URL) -> [ClipTab]? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([ClipTab].self, from: data),
              !decoded.isEmpty
        else { return nil }
        return decoded
    }

    /// Load just the volatile clipboard items.
    private static func loadClipboardItems(from url: URL) -> [ClipItem]? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([ClipItem].self, from: data)
        else { return nil }
        return decoded
    }

    /// Persist the tab structure (all tabs, but with the clipboard tab's items stripped so
    /// this file stays stable and sync-friendly).
    private func saveTabs() {
        var structural = tabs
        if structural.indices.contains(clipboardTabIndex) {
            structural[clipboardTabIndex].items = []
        }
        if let data = try? TabStore.makeEncoder().encode(structural) {
            try? data.write(to: tabsURL)
        }
    }

    /// Persist only the clipboard tab's items (the volatile, non-synced file).
    private func saveClipboard() {
        let items = tabs.indices.contains(clipboardTabIndex) ? tabs[clipboardTabIndex].items : []
        if let data = try? TabStore.makeEncoder().encode(items) {
            try? data.write(to: clipboardURL)
        }
    }

    /// Save whichever file a change to `tabIndex` affects: clipboard.json for the auto-capture
    /// tab, tabs.json otherwise.
    private func save(affectedTab tabIndex: Int) {
        if tabIndex == clipboardTabIndex { saveClipboard() } else { saveTabs() }
    }
}
