import Foundation

/// One-time move from the old single-folder layout (`<configDir>/copy-paste/` holding
/// `clipboard.json`, `tabs.json` and one shared `blobs/`) to the split layout:
/// `<clipboardPath>/{clipboard.json, blobs/}` and `<snippetPath>/{tabs.json, blobs/}`.
enum CopyPasteStorage {
    private static let fm = FileManager.default

    /// Moves legacy files into the configured folders when they aren't there yet. Returns
    /// false if anything went wrong — callers must then skip orphan-blob cleanup, since
    /// blob files may still sit in a folder whose index no longer references them.
    static func migrateLegacyLayout(
        legacyDir: URL,
        clipboardDir: URL,
        snippetDir: URL,
        clipboardFile: String,
        tabsFile: String
    ) -> Bool {
        let legacyBlobs = legacyDir.appendingPathComponent("blobs")
        let legacyClip = legacyDir.appendingPathComponent(clipboardFile)
        let legacyTabs = legacyDir.appendingPathComponent(tabsFile)
        let snippetBlobs = snippetDir.appendingPathComponent("blobs")
        let decoder = TabStore.makeDecoder()

        // Blobs referenced by snippet tabs (tab 0 is the clipboard tab and is stored item-less).
        let legacyTabList = (try? Data(contentsOf: legacyTabs)).flatMap { try? decoder.decode([ClipTab].self, from: $0) }
        let snippetRefs = Set((legacyTabList ?? []).dropFirst().flatMap(\.items).compactMap(\.blobFilename))

        // 1. Clipboard history → clipboardDir.
        if !same(legacyDir, clipboardDir), exists(legacyClip),
           !exists(clipboardDir.appendingPathComponent(clipboardFile)) {
            guard let data = try? Data(contentsOf: legacyClip),
                  let items = try? decoder.decode([ClipItem].self, from: data) else {
                NSLog("mac-tools: can't read legacy \(legacyClip.path); leaving it in place")
                return false
            }
            // A blob shared with a snippet that stays in the legacy folder must be copied.
            let keepInPlace = same(legacyBlobs, snippetBlobs) ? snippetRefs : []
            guard move(blobs: items.compactMap(\.blobFilename), from: legacyBlobs,
                       to: clipboardDir.appendingPathComponent("blobs"), copying: keepInPlace,
                       index: legacyClip, indexTo: clipboardDir.appendingPathComponent(clipboardFile))
            else { return false }
        }

        // 2. Snippet tabs → snippetDir.
        if !same(legacyDir, snippetDir), exists(legacyTabs),
           !exists(snippetDir.appendingPathComponent(tabsFile)) {
            guard legacyTabList != nil else {
                NSLog("mac-tools: can't read legacy \(legacyTabs.path); leaving it in place")
                return false
            }
            guard move(blobs: Array(snippetRefs), from: legacyBlobs, to: snippetBlobs, copying: [],
                       index: legacyTabs, indexTo: snippetDir.appendingPathComponent(tabsFile))
            else { return false }
        }

        // 3. The legacy folder is no longer used by either index: whatever is left in its
        // blobs/ is unreferenced. Remove it (and the folders, if empty).
        let clipDone = same(legacyDir, clipboardDir) ? false : !exists(legacyClip)
        let tabsDone = same(legacyDir, snippetDir) ? false : !exists(legacyTabs)
        if clipDone, tabsDone, exists(legacyBlobs) {
            let leftovers = (try? fm.contentsOfDirectory(atPath: legacyBlobs.path)) ?? []
            leftovers.forEach { try? fm.removeItem(at: legacyBlobs.appendingPathComponent($0)) }
            try? fm.removeItem(at: legacyBlobs)
            let remaining = (try? fm.contentsOfDirectory(atPath: legacyDir.path)) ?? []
            if remaining.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: legacyDir)
            }
            if !leftovers.isEmpty {
                NSLog("mac-tools: removed \(leftovers.count) unreferenced legacy blob(s)")
            }
        }
        return true
    }

    /// Move `blobs` (those in `copying` are copied instead) and then the index file. On any
    /// failure, moved blobs are put back so the legacy layout stays intact.
    private static func move(
        blobs: [String], from src: URL, to dst: URL, copying: Set<String>,
        index: URL, indexTo: URL
    ) -> Bool {
        var moved: [String] = []
        var copied: [String] = []
        func rollback() {
            for name in moved { try? fm.moveItem(at: dst.appendingPathComponent(name), to: src.appendingPathComponent(name)) }
            for name in copied { try? fm.removeItem(at: dst.appendingPathComponent(name)) }
        }
        do {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            try fm.createDirectory(at: indexTo.deletingLastPathComponent(), withIntermediateDirectories: true)
            for name in Set(blobs) {
                let from = src.appendingPathComponent(name)
                let to = dst.appendingPathComponent(name)
                guard exists(from), !exists(to) else { continue }
                if copying.contains(name) {
                    try fm.copyItem(at: from, to: to); copied.append(name)
                } else {
                    try fm.moveItem(at: from, to: to); moved.append(name)
                }
            }
            try fm.moveItem(at: index, to: indexTo)
            NSLog("mac-tools: migrated \(index.lastPathComponent) and \(moved.count + copied.count) blob(s) to \(indexTo.deletingLastPathComponent().path)")
            return true
        } catch {
            NSLog("mac-tools: storage migration failed (\(error)); rolling back")
            rollback()
            return false
        }
    }

    private static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
