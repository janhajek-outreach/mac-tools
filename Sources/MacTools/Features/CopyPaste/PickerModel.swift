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

    /// When non-nil, the row at this index is in inline-edit mode (text) — F2.
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
        editingIndex != nil || labelingIndex != nil || copyToTabForIndex != nil || namingTab || confirmDeleteTabIndex != nil
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
    }

    func clampSelection() {
        if filtered.isEmpty { selection = 0 }
        else { selection = min(max(0, selection), filtered.count - 1) }
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    /// Plain up/down: collapses any multi-selection back to a single row.
    func moveSelectionUp() {
        guard !filtered.isEmpty else { return }
        selection = max(0, selection - 1)
        selectionAnchor = selection
        selectedIndices = [selection]
    }

    func moveSelectionDown() {
        guard !filtered.isEmpty else { return }
        selection = min(filtered.count - 1, selection + 1)
        selectionAnchor = selection
        selectedIndices = [selection]
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
        } else if searchActive && !query.isEmpty {
            query = ""; selectSingle(0)
        } else if searchActive {
            searchActive = false; query = ""; selectSingle(0)
        } else {
            onCancel()
        }
    }
}
