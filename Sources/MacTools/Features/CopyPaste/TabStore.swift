import Foundation
import Combine

/// How a tab's items are shown in the picker.
enum TabLayout: String, Codable {
    case list
    case tiles
}

/// A named collection of items. Tab 0 is the auto-capture "Clipboard" tab.
struct ClipTab: Codable, Identifiable {
    var id: UUID
    var name: String
    var items: [ClipItem]
    /// Layout chosen for this tab (⌘G). Nil = the configured default; omitted from JSON then.
    var layout: TabLayout?

    init(id: UUID = UUID(), name: String, items: [ClipItem] = [], layout: TabLayout? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.layout = layout
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
        clipboardFileURL: URL? = nil,
        cleanOrphanBlobs: Bool = false
    ) {
        self.maxHistory = maxHistory
        let tabsU = tabsFileURL ?? AppPaths.dataFile("copy-paste", "tabs.json")
        let clipU = clipboardFileURL ?? AppPaths.dataFile("copy-paste", "clipboard.json")
        self.tabsURL = tabsU
        self.clipboardURL = clipU

        // Load the tab structure (custom tabs + names; clipboard tab present but item-less).
        var loadedTabs: [ClipTab]
        let tabsLoaded: Bool
        if let loaded = TabStore.loadTabs(from: tabsU), !loaded.isEmpty {
            loadedTabs = loaded
            tabsLoaded = true
        } else {
            loadedTabs = [ClipTab(name: clipboardTabName)]
            loadedTabs.append(contentsOf: snippetTabNames.map { ClipTab(name: $0) })
            tabsLoaded = false
        }
        // Merge the volatile clipboard items into the clipboard tab.
        let clipboardFileExists = FileManager.default.fileExists(atPath: clipU.path)
        var clipboardLoaded = false
        if let clipItems = TabStore.loadClipboardItems(from: clipU),
           loadedTabs.indices.contains(0) {
            loadedTabs[0].items = clipItems
            clipboardLoaded = true
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
        if cleanOrphanBlobs {
            removeOrphanBlobs(clipboardLoaded: clipboardLoaded, tabsLoaded: tabsLoaded)
        }
        refreshReferences()
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
        let removed = tabs.remove(at: index)
        for item in removed.items { freeBlob(of: item, in: BlobStore.snippets) }
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

    // MARK: Layout

    /// Layout used by tabs that haven't chosen one (`ui.defaultLayout`).
    var defaultLayout: TabLayout = .list

    func layout(ofTab index: Int) -> TabLayout {
        guard tabs.indices.contains(index) else { return defaultLayout }
        return tabs[index].layout ?? defaultLayout
    }

    /// Switch a tab between list and tiles. Stored per tab in tabs.json (the Clipboard tab's
    /// entry there too — only its items live in clipboard.json).
    func toggleLayout(ofTab index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].layout = layout(ofTab: index) == .list ? .tiles : .list
        saveTabs()
    }

    // MARK: Blob directories

    /// The Clipboard tab keeps its blobs in the clipboard dir; every other tab in the snippet dir.
    func blobDir(forTab tabIndex: Int) -> BlobDir {
        tabIndex == clipboardTabIndex ? BlobStore.clipboard : BlobStore.snippets
    }

    // MARK: File status (linked originals + blobs)

    /// Items whose file can't be found — a linked original that's gone, or a blob that was
    /// removed (e.g. the Caches folder was cleaned). Not persisted; refreshed on show.
    @Published private(set) var missingIDs: Set<UUID> = []
    /// Last resolved location of each linked item's original file.
    @Published private(set) var resolvedURLs: [UUID: URL] = [:]

    private let fileQueue = DispatchQueue(label: "mac-tools.copy-paste.files", qos: .userInitiated)

    func isMissing(_ item: ClipItem) -> Bool {
        missingIDs.contains(item.id)
    }

    /// Where the item's bytes live: its blob, or the linked original (nil if unresolved).
    func contentURL(for item: ClipItem, inTab tabIndex: Int) -> URL? {
        if let blob = item.blobFilename { return blobDir(forTab: tabIndex).url(for: blob) }
        return item.isReference ? resolvedURLs[item.id] : nil
    }

    /// Stored GIF files across all tabs (used to prune cached GIF video thumbnails).
    func storedGIFURLs() -> [URL] {
        tabs.indices.flatMap { t in
            tabs[t].items.compactMap { item -> URL? in
                guard let blob = item.blobFilename else { return nil }
                let url = blobDir(forTab: t).url(for: blob)
                return BlobStore.isGIF(url) ? url : nil
            }
        }
    }

    /// Re-check every item's file in the background: which linked originals are gone, where
    /// the others live now (bookmarks follow moves/renames, stale ones get refreshed), and
    /// which blobs have disappeared.
    func refreshReferences() {
        var refs: [ClipItem] = []
        var blobs: [(UUID, URL)] = []
        for t in tabs.indices {
            let dir = blobDir(forTab: t)
            for item in tabs[t].items {
                if item.isReference { refs.append(item) }
                else if let blob = item.blobFilename { blobs.append((item.id, dir.url(for: blob))) }
            }
        }
        fileQueue.async {
            var missing = Set<UUID>()
            var urls: [UUID: URL] = [:]
            var refreshed: [UUID: Data] = [:]
            for item in refs {
                guard let bm = item.bookmark, let r = FileReference.resolve(bm) else {
                    missing.insert(item.id); continue
                }
                urls[item.id] = r.url
                if let fresh = r.refreshed { refreshed[item.id] = fresh }
            }
            for (id, url) in blobs where !FileManager.default.fileExists(atPath: url.path) {
                missing.insert(id)
            }
            DispatchQueue.main.async {
                self.missingIDs = missing
                self.resolvedURLs = urls
                for (id, bm) in refreshed { self.updateBookmark(bm, for: id) }
            }
        }
    }

    /// Record whether a single item's file was found (e.g. right before pasting it).
    func noteResolution(of item: ClipItem, url: URL?) {
        if let url {
            missingIDs.remove(item.id)
            if item.isReference { resolvedURLs[item.id] = url }
        } else {
            missingIDs.insert(item.id); resolvedURLs[item.id] = nil
        }
    }

    /// Locate an image/file item's bytes on disk right now (following a linked original's
    /// bookmark), updating its missing state. Nil for text items or when the file is gone.
    func locateFile(for item: ClipItem, inTab tabIndex: Int) -> URL? {
        guard item.kind != .text else { return nil }
        var url: URL?
        if let blob = item.blobFilename {
            let dir = blobDir(forTab: tabIndex)
            url = dir.exists(blob) ? dir.url(for: blob) : nil
        } else if let bm = item.bookmark {
            url = FileReference.resolve(bm)?.url
        }
        noteResolution(of: item, url: url)
        return url
    }

    private func updateBookmark(_ bookmark: Data, for id: UUID) {
        for t in tabs.indices {
            if let i = tabs[t].items.firstIndex(where: { $0.id == id }) {
                tabs[t].items[i].bookmark = bookmark
                save(affectedTab: t)
            }
        }
    }

    // MARK: Auto-capture (clipboard tab only)

    func capture(_ item: ClipItem) {
        if item.isReference, let bm = item.bookmark {
            noteResolution(of: item, url: FileReference.resolve(bm)?.url)
        }
        var items = tabs[clipboardTabIndex].items
        // De-dup: remove an existing item with the same content.
        if let idx = items.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
            // Free its blob if it was an image/file we're about to replace.
            freeBlob(of: items[idx], in: BlobStore.clipboard)
            items.remove(at: idx)
        }
        items.insert(item, at: 0)
        if items.count > maxHistory {
            for removed in items[maxHistory...] {
                freeBlob(of: removed, in: BlobStore.clipboard)
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
        freeBlob(of: removed, in: blobDir(forTab: tabIndex))
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

    func setName(_ name: String, for id: UUID, in tabIndex: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id, in: tabIndex) { item in
            guard item.kind != .text else { return }
            item.originalName = trimmed
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

    /// Copy an item into another tab (F5). Tabs are independent, so the destination always
    /// gets its own blob — linked items are materialized into a full copy.
    func copyItem(_ id: UUID, from sourceTab: Int, to destTab: Int) {
        copyItems([id], from: sourceTab, to: destTab)
    }

    /// Add a downloaded image (⌘D) as a new item directly above the link it came from. The
    /// tab is looked up by id since the download may finish after tabs changed; if the link
    /// item is gone, the image goes to the top. Returns false (and deletes the file) if the
    /// tab no longer exists.
    @discardableResult
    func insertDownloadedImage(file: URL, ext: String, name: String, aboveItem sourceID: UUID, inTabID tabID: UUID) -> Bool {
        guard let t = tabs.firstIndex(where: { $0.id == tabID }) else {
            try? FileManager.default.removeItem(at: file)
            return false
        }
        guard let blob = blobDir(forTab: t).moveFile(from: file, ext: ext) else {
            try? FileManager.default.removeItem(at: file)
            return false
        }
        let item = ClipItem(kind: .image, blobFilename: blob, originalName: name)
        let index = tabs[t].items.firstIndex(where: { $0.id == sourceID }) ?? 0
        tabs[t].items.insert(item, at: index)
        if t == clipboardTabIndex, tabs[t].items.count > maxHistory {
            for removed in tabs[t].items[maxHistory...] { freeBlob(of: removed, in: BlobStore.clipboard) }
            tabs[t].items.removeLast(tabs[t].items.count - maxHistory)
        }
        save(affectedTab: t)
        return true
    }

    // MARK: Multi-item operations

    /// Delete many items (by id) from a tab.
    func delete(_ ids: [UUID], in tabIndex: Int) {
        guard tabs.indices.contains(tabIndex) else { return }
        let idSet = Set(ids)
        let removed = tabs[tabIndex].items.filter { idSet.contains($0.id) }
        tabs[tabIndex].items.removeAll { idSet.contains($0.id) }
        for item in removed { freeBlob(of: item, in: blobDir(forTab: tabIndex)) }
        save(affectedTab: tabIndex)
    }

    /// Copy many items to another tab, preserving order (top-most first). File work runs in
    /// the background (linked originals can be GBs); items appear once copied. Calls
    /// `completion` on the main thread with the number of items that couldn't be copied.
    func copyItems(_ ids: [UUID], from sourceTab: Int, to destTab: Int, completion: ((Int) -> Void)? = nil) {
        guard tabs.indices.contains(sourceTab), tabs.indices.contains(destTab), sourceTab != destTab else { return }
        let items = ids.compactMap { id in tabs[sourceTab].items.first(where: { $0.id == id }) }
        guard !items.isEmpty else { return }
        let destID = tabs[destTab].id
        let from = blobDir(forTab: sourceTab)
        let to = blobDir(forTab: destTab)
        fileQueue.async {
            let copies = items.map { TabStore.independentCopy(of: $0, from: from, to: to) }
            DispatchQueue.main.async {
                // The destination tab may have moved/been deleted meanwhile; find it by id.
                guard let dest = self.tabs.firstIndex(where: { $0.id == destID }) else {
                    copies.compactMap { $0?.blobFilename }.forEach(to.delete)
                    return
                }
                self.tabs[dest].items.insert(contentsOf: copies.compactMap { $0 }, at: 0)
                self.save(affectedTab: dest)
                completion?(copies.filter { $0 == nil }.count)
            }
        }
    }

    /// A copy of `item` with a new id and its own blob in `to`. Nil if the bytes can't be
    /// copied (e.g. a linked original or a blob has gone missing).
    private static func independentCopy(of item: ClipItem, from: BlobDir, to: BlobDir) -> ClipItem? {
        var copy = item
        copy.id = UUID()
        if let blob = item.blobFilename {
            guard let newBlob = to.copyFile(from: from.url(for: blob)) else { return nil }
            copy.blobFilename = newBlob
        } else if let bm = item.bookmark {
            guard let url = FileReference.resolve(bm)?.url,
                  let newBlob = to.copyFile(from: url) else { return nil }
            copy.blobFilename = newBlob
            copy.bookmark = nil
        }
        return copy
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

    /// Move the given items to the top of their tab, preserving their relative order.
    /// Used after a paste so the most recently used item is always first.
    func promoteToTop(_ ids: [UUID], in tabIndex: Int) {
        guard !ids.isEmpty, tabs.indices.contains(tabIndex) else { return }
        let idSet = Set(ids)
        var items = tabs[tabIndex].items
        let promoted = items.filter { idSet.contains($0.id) }
        guard !promoted.isEmpty else { return }
        // Already at the top in the same order? Nothing to do (avoids a pointless write).
        if Array(items.prefix(promoted.count)).map(\.id) == promoted.map(\.id) { return }
        items.removeAll { idSet.contains($0.id) }
        items.insert(contentsOf: promoted, at: 0)
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

    /// Delete an item's blob from `dir` unless another item stored in the same directory
    /// still references it (call after the item has been removed, or it's excluded by id).
    private func freeBlob(of item: ClipItem, in dir: BlobDir) {
        guard let blob = item.blobFilename else { return }
        let target = dir.dir.standardizedFileURL
        let stillUsed = tabs.indices.contains { t in
            blobDir(forTab: t).dir.standardizedFileURL == target
                && tabs[t].items.contains { $0.id != item.id && $0.blobFilename == blob }
        }
        if !stillUsed { dir.delete(blob) }
    }

    /// Delete files in each blob directory that no item references. Only runs for a directory
    /// when every file listing items stored there loaded cleanly — never on a failed load.
    private func removeOrphanBlobs(clipboardLoaded: Bool, tabsLoaded: Bool) {
        var dirs: [URL: (dir: BlobDir, refs: Set<String>, safe: Bool)] = [:]
        for t in tabs.indices {
            let dir = blobDir(forTab: t)
            let key = dir.dir.standardizedFileURL
            let loaded = t == clipboardTabIndex ? clipboardLoaded : tabsLoaded
            var entry = dirs[key] ?? (dir, [], true)
            entry.refs.formUnion(tabs[t].items.compactMap(\.blobFilename))
            entry.safe = entry.safe && loaded
            dirs[key] = entry
        }
        for (_, entry) in dirs where entry.safe {
            let orphans = entry.dir.allFilenames().filter { !entry.refs.contains($0) }
            orphans.forEach(entry.dir.delete)
            if !orphans.isEmpty {
                NSLog("mac-tools: removed \(orphans.count) unreferenced blob(s) from \(entry.dir.dir.path)")
            }
        }
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

    static func makeDecoder() -> JSONDecoder {
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
            TabStore.write(data, to: tabsURL)
        }
    }

    /// Persist only the clipboard tab's items (the volatile, non-synced file).
    private func saveClipboard() {
        let items = tabs.indices.contains(clipboardTabIndex) ? tabs[clipboardTabIndex].items : []
        if let data = try? TabStore.makeEncoder().encode(items) {
            TabStore.write(data, to: clipboardURL)
        }
    }

    /// Write a data file, creating its folder first (e.g. after the Caches folder was wiped).
    private static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    /// Save whichever file a change to `tabIndex` affects: clipboard.json for the auto-capture
    /// tab, tabs.json otherwise.
    private func save(affectedTab tabIndex: Int) {
        if tabIndex == clipboardTabIndex { saveClipboard() } else { saveTabs() }
    }
}
