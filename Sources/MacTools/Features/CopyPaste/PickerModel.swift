import SwiftUI
import Combine
import AppKit

/// UI state for the picker. The feature controller drives navigation & actions via keys.
final class PickerModel: ObservableObject {
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Anchor index for shift-range selection.
    @Published var selectionAnchor: Int = 0
    /// All currently selected row indices (into `filtered`). Always contains `selection`.
    @Published var selectedIndices: Set<Int> = [0]
    @Published var searchActive: Bool = false

    /// When non-nil, the row at this index is in inline-edit mode (text, or image/file name) — F2.
    @Published var editingIndex: Int? = nil
    @Published var editingText: String = ""

    /// When non-nil, a label prompt (F3) is open for this index.
    @Published var labelingIndex: Int? = nil
    @Published var labelText: String = ""

    /// When non-nil, the F5 "copy to tab" picker is open for this index.
    @Published var copyToTabForIndex: Int? = nil

    /// When true, the tab-name prompt is open.
    @Published var namingTab: Bool = false
    /// The index of the tab being renamed, or nil when adding a new tab.
    @Published var namingTabIndex: Int? = nil
    @Published var tabNameText: String = ""

    /// When non-nil, a delete-confirmation prompt is open for this tab index.
    @Published var confirmDeleteTabIndex: Int? = nil
    @Published var confirmDeleteText: String = ""

    /// True while the picker window is on screen; GIF thumbnails only animate when set.
    @Published var isVisible: Bool = false

    /// A copy-to-tab that needs confirmation because it materializes large linked files.
    struct PendingCopy {
        let ids: [UUID]
        let sourceTab: Int
        let destTab: Int
        let destName: String
        let itemCount: Int
        /// Total size of the linked originals that will be copied.
        let bytes: Int64
        let freeBytes: Int64?
        var hasEnoughSpace: Bool { freeBytes.map { $0 > bytes } ?? true }
    }
    @Published var pendingCopy: PendingCopy? = nil

    /// A link found by ⌘D that points to an image.
    struct DownloadCandidate {
        let sourceID: UUID
        let url: URL
        /// Size reported by the server, or nil when unknown.
        let size: Int64?
    }

    /// Linked images over `imgDownloadLimitSize`, waiting for confirmation before download.
    struct PendingDownload {
        let candidates: [DownloadCandidate]
        let tabID: UUID
        let limitBytes: Int64
        /// Sum of the known sizes (some may be unknown, i.e. only known to exceed the limit).
        var knownBytes: Int64 { candidates.compactMap(\.size).reduce(0, +) }
        var hasUnknownSize: Bool { candidates.contains { $0.size == nil } }
    }
    /// Not cleared when the panel reopens: downloads finish in the background, and the
    /// question should still be there when the user comes back.
    @Published var pendingDownload: PendingDownload? = nil

    /// Transient message shown in the footer (e.g. "File is missing — can't paste").
    @Published var statusMessage: String? = nil

    func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }

    let store: TabStore

    var onCommit: (ClipItem) -> Void = { _ in }
    var onCommitMany: ([ClipItem]) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(store: TabStore) {
        self.store = store
    }

    var filtered: [ClipItem] {
        let items = store.currentItems
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            ($0.text?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.label?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedItem: ClipItem? {
        filtered.indices.contains(selection) ? filtered[selection] : nil
    }

    /// Items for all selected rows, in list order.
    var selectedItems: [ClipItem] {
        let f = filtered
        return selectedIndices.sorted().compactMap { f.indices.contains($0) ? f[$0] : nil }
    }

    /// True when more than one row is selected.
    var hasMultiSelection: Bool { selectedIndices.count > 1 }

    var isModalOpen: Bool {
        editingIndex != nil || labelingIndex != nil || copyToTabForIndex != nil || namingTab
            || confirmDeleteTabIndex != nil || pendingCopy != nil || pendingDownload != nil
    }

    func reset() {
        query = ""
        selection = 0
        selectionAnchor = 0
        selectedIndices = [0]
        searchActive = false
        editingIndex = nil
        labelingIndex = nil
        copyToTabForIndex = nil
        namingTab = false
        namingTabIndex = nil
        confirmDeleteTabIndex = nil
        confirmDeleteText = ""
        pendingCopy = nil
        statusMessage = nil
    }

    func clampSelection() {
        if filtered.isEmpty { selection = 0 }
        else { selection = min(max(0, selection), filtered.count - 1) }
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    /// Plain up/down: collapses any multi-selection back to a single row.
    /// Wraps around at the list edges (top -> bottom, bottom -> top).
    func moveSelectionUp() {
        let count = filtered.count
        guard count > 0 else { return }
        selection = selection <= 0 ? count - 1 : selection - 1
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    func moveSelectionDown() {
        let count = filtered.count
        guard count > 0 else { return }
        selection = selection >= count - 1 ? 0 : selection + 1
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    /// Page up/down: jump the selection by `step` rows (collapses multi-selection).
    func pageUp(by step: Int) {
        guard !filtered.isEmpty else { return }
        selection = max(0, selection - max(1, step))
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    func pageDown(by step: Int) {
        guard !filtered.isEmpty else { return }
        selection = min(filtered.count - 1, selection + max(1, step))
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    /// Jump to the first / last row (collapses multi-selection).
    func moveSelectionToStart() {
        guard !filtered.isEmpty else { return }
        selectSingle(0)
    }

    func moveSelectionToEnd() {
        guard !filtered.isEmpty else { return }
        selectSingle(filtered.count - 1)
    }

    /// Shift+up/down: extend the selection range from the anchor.
    func extendSelectionUp() {
        guard !filtered.isEmpty else { return }
        selection = max(0, selection - 1)
        rebuildRangeFromAnchor()
    }

    func extendSelectionDown() {
        guard !filtered.isEmpty else { return }
        selection = min(filtered.count - 1, selection + 1)
        rebuildRangeFromAnchor()
    }

    private func rebuildRangeFromAnchor() {
        let lo = min(selectionAnchor, selection)
        let hi = max(selectionAnchor, selection)
        selectedIndices = Set(lo...hi)
    }

    /// Set a single selection (e.g. from a click).
    func selectSingle(_ index: Int) {
        selection = index
        selectionAnchor = index
        selectedIndices = [index]
    }

    /// Extend the current selection to the anchor (shift-click).
    func selectRangeToAnchor() {
        guard !filtered.isEmpty else { return }
        rebuildRangeFromAnchor()
    }

    func commit() { if let item = selectedItem { onCommit(item) } }

    // MARK: Tiles layout

    /// Tiles per row and rows per page in the tiles layout (set from the window/tile size).
    var columns = 4
    var pageRows = 2

    var isTiles: Bool { store.layout(ofTab: store.currentTab) == .tiles }

    /// Tiles: move the cursor by `delta` items (±1 for left/right, ±columns for up/down),
    /// clamped to the list. With `extend`, grow the range from the anchor instead.
    func moveInGrid(by delta: Int, extend: Bool = false) {
        let count = filtered.count
        guard count > 0 else { return }
        var target = selection + delta
        if target < 0 { guard abs(delta) == 1 else { return }; target = 0 }
        if target >= count {
            // Down into a shorter last row lands on the last item; from the last row, stay put.
            let cols = max(1, columns)
            guard abs(delta) == 1 || selection / cols < (count - 1) / cols else { return }
            target = count - 1
        }
        selection = target
        if extend {
            rebuildRangeFromAnchor()
        } else {
            selectionAnchor = selection
            selectedIndices = [selection]
        }
    }

    func activateSearch() { searchActive = true }

    func escape() {
        if isModalOpen {
            editingIndex = nil
            labelingIndex = nil
            copyToTabForIndex = nil
            namingTab = false
            namingTabIndex = nil
            confirmDeleteTabIndex = nil
            confirmDeleteText = ""
            pendingCopy = nil
            pendingDownload = nil
        } else if searchActive && !query.isEmpty {
            query = ""; selectSingle(0)
        } else if searchActive {
            searchActive = false; query = ""; selectSingle(0)
        } else {
            onCancel()
        }
    }
}
