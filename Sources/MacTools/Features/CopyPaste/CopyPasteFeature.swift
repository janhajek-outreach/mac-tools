import Cocoa
import SwiftUI
import Carbon.HIToolbox

/// The copy-paste clipboard manager feature.
final class CopyPasteFeature: NSObject, Feature, NSWindowDelegate {
    let id = "copy-paste"
    let displayName = "Copy Paste"

    private let config: CopyPasteConfig
    private let store: TabStore
    private let model: PickerModel

    private var window: NSWindow!
    private var showListHotKey: HotKey?
    private var monitor: ClipboardMonitor!
    private var localKeyMonitor: Any?

    private var previousApp: NSRunningApplication?

    init(config: CopyPasteConfig) {
        self.config = config
        // Configure storage paths from config before creating stores.
        BlobStore.configure(dir: AppPaths.resolve(config.blobDir, feature: "copy-paste"))
        let tabsURL = AppPaths.dataFile("copy-paste", config.tabsFile)
        let clipboardURL = AppPaths.dataFile("copy-paste", config.clipboardFile)
        self.store = TabStore(
            maxHistory: config.maxHistory,
            snippetTabNames: config.snippetTabs,
            clipboardTabName: config.clipboardTabName,
            tabsFileURL: tabsURL,
            clipboardFileURL: clipboardURL
        )
        self.model = PickerModel(store: store)
        super.init()
    }

    func activate() {
        setupModel()
        setupWindow()
        setupClipboardMonitor()
        registerGlobalHotKey()
    }

    func menuItems() -> [FeatureMenuItem] {
        [
            FeatureMenuItem(title: "Show Clipboard (\(config.showList.displayLabel))") { [weak self] in
                self?.showWindow()
            },
        ]
    }

    // MARK: Setup

    private func setupModel() {
        model.onCommit = { [weak self] item in self?.pasteAndHide(item) }
        model.onCommitMany = { [weak self] items in self?.pasteManyAndHide(items) }
        model.onCancel = { [weak self] in self?.hideWindow() }
    }

    private func setupWindow() {
        let content = NSHostingView(rootView: PanelView(model: model, config: config))
        window = KeyablePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: config.window.width, height: config.window.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.contentView = content
        window.center()
        window.isReleasedWhenClosed = false
        window.level = config.window.floating ? .floating : .normal
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.delegate = self
    }

    private func setupClipboardMonitor() {
        monitor = ClipboardMonitor { [weak self] item in
            self?.store.capture(item)
        }
        monitor.start(interval: config.pollInterval)
    }

    private func registerGlobalHotKey() {
        showListHotKey = HotKey(shortcut: config.showList, id: 1) { [weak self] in
            self?.toggleWindow()
        }
        if showListHotKey == nil {
            NSLog("mac-tools: failed to register copy-paste showList hotkey")
        }
    }

    // MARK: Window control

    private func showWindow() {
        previousApp = NSWorkspace.shared.frontmostApplication
        model.reset()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installLocalKeyMonitor()
    }

    private func toggleWindow() {
        if window.isVisible { hideWindow(returnFocus: true) } else { showWindow() }
    }

    /// When the user clicks another app/window, dismiss ourselves so the next reopen is fresh.
    func windowDidResignKey(_ notification: Notification) {
        if config.window.hideOnClickAway, window.isVisible { hideWindow() }
    }

    private func hideWindow(returnFocus: Bool = false) {
        removeLocalKeyMonitor()
        window.orderOut(nil)
        if returnFocus { previousApp?.activate() }
    }

    private func pasteAndHide(_ item: ClipItem) {
        // Put the content on the clipboard first.
        Paster.setClipboard(item)
        monitor.syncChangeCount()

        // If we can't post key events, just hand off the clipboard and let the user paste.
        guard Paster.ensureAccessibilityPermission(prompt: false) else {
            hideWindow(returnFocus: true)
            Paster.warnAccessibilityMissing()
            return
        }

        // Hide our window and reactivate the previous app before pasting into it.
        removeLocalKeyMonitor()
        window.orderOut(nil)
        previousApp?.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Paster.simulatePaste()
        }
    }

    /// Paste multiple text items joined by the configured separator.
    private func pasteManyAndHide(_ items: [ClipItem]) {
        let texts = items.compactMap { $0.kind == .text ? $0.text : nil }
        guard !texts.isEmpty else { hideWindow(returnFocus: true); return }
        let joined = texts.joined(separator: config.multiSelectPasteSeparator)
        Paster.setPlainText(joined)
        monitor.syncChangeCount()

        guard Paster.ensureAccessibilityPermission(prompt: false) else {
            hideWindow(returnFocus: true)
            Paster.warnAccessibilityMissing()
            return
        }
        removeLocalKeyMonitor()
        window.orderOut(nil)
        previousApp?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Paster.simulatePaste()
        }
    }

    // MARK: Local key handling

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKey(event)
        }
    }

    private func removeLocalKeyMonitor() {
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }

    private var currentItemID: UUID? { model.selectedItem?.id }
    private var tabIndex: Int { store.currentTab }
    private var keys: CopyPasteConfig.KeyBindings { config.keys }

    private func isCommit(_ e: NSEvent) -> Bool {
        keys.commit.matches(e) || Int(e.keyCode) == kVK_ANSI_KeypadEnter
    }
    private func isCancel(_ e: NSEvent) -> Bool { keys.cancel.matches(e) }

    /// Returns nil to swallow the event, or the event to let it propagate.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // ---- Quit app ----
        if keys.quit.matches(event) { NSApp.terminate(nil); return nil }

        // ---- Modal: label prompt ----
        if model.labelingIndex != nil {
            if isCommit(event) {
                if let id = itemID(at: model.labelingIndex!) {
                    store.setLabel(model.labelText, for: id, in: tabIndex)
                }
                model.labelingIndex = nil
                return nil
            }
            if isCancel(event) { model.labelingIndex = nil; return nil }
            return event
        }

        // ---- Modal: confirm tab delete (type the confirm word) ----
        if let idx = model.confirmDeleteTabIndex {
            if isCommit(event) {
                let typed = model.confirmDeleteText.trimmingCharacters(in: .whitespaces).lowercased()
                if typed == config.deleteTabConfirmWord.lowercased() {
                    store.removeTab(at: idx)
                    model.selectSingle(0)
                    model.confirmDeleteTabIndex = nil
                    model.confirmDeleteText = ""
                }
                return nil
            }
            if isCancel(event) {
                model.confirmDeleteTabIndex = nil; model.confirmDeleteText = ""; return nil
            }
            return event
        }

        // ---- Modal: tab name prompt ----
        if model.namingTab {
            if isCommit(event) {
                let name = model.tabNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let idx = model.namingTabIndex {
                    store.renameTab(at: idx, to: name)
                } else {
                    store.addTab(name: name.isEmpty ? "New Tab" : name)
                    model.selectSingle(0)
                }
                model.namingTab = false; model.namingTabIndex = nil
                return nil
            }
            if isCancel(event) { model.namingTab = false; model.namingTabIndex = nil; return nil }
            return event
        }

        // ---- Modal: inline text edit ----
        if model.editingIndex != nil {
            if isCommit(event), !event.modifierFlags.contains(.shift) {
                if let id = itemID(at: model.editingIndex!) {
                    store.setText(model.editingText, for: id, in: tabIndex)
                }
                model.editingIndex = nil
                return nil
            }
            if isCancel(event) { model.editingIndex = nil; return nil }
            return event
        }

        // ---- Modal: copy-to-tab picker ----
        if let srcIndex = model.copyToTabForIndex {
            if isCancel(event) { model.copyToTabForIndex = nil; return nil }
            if let dest = tabNumberPressed(event), dest != store.currentTab {
                // Copy all selected items if multi-selected, else just the source row.
                if model.hasMultiSelection {
                    store.copyItems(model.selectedItems.map(\.id), from: store.currentTab, to: dest)
                } else if let id = itemID(at: srcIndex) {
                    store.copyItem(id, from: store.currentTab, to: dest)
                }
                model.copyToTabForIndex = nil
                return nil
            }
            return nil // swallow other keys while picking
        }

        // ---- Tab switching ----
        if keys.prevTab.matches(event) { store.prevTab(); model.selectSingle(0); return nil }
        if keys.nextTab.matches(event) { store.nextTab(); model.selectSingle(0); return nil }

        // ---- Tab management ----
        if keys.newTab.matches(event) {
            model.tabNameText = ""; model.namingTabIndex = nil; model.namingTab = true
            return nil
        }
        if keys.renameTab.matches(event) {
            model.tabNameText = store.tabs.indices.contains(store.currentTab) ? store.tabs[store.currentTab].name : ""
            model.namingTabIndex = store.currentTab; model.namingTab = true
            return nil
        }
        if keys.closeTab.matches(event) {
            if store.currentTab != store.clipboardTabIndex {
                if store.tabs[store.currentTab].items.isEmpty {
                    store.removeTab(at: store.currentTab); model.selectSingle(0)
                } else {
                    model.confirmDeleteText = ""; model.confirmDeleteTabIndex = store.currentTab
                }
            }
            return nil
        }

        // ---- Reorder item(s) within list (only when not filtering) ----
        if keys.moveUp.matches(event) {
            if model.query.isEmpty { reorder(by: -1) }
            return nil
        }
        if keys.moveDown.matches(event) {
            if model.query.isEmpty { reorder(by: 1) }
            return nil
        }

        // ---- Extend selection (shift + arrows) ----
        if keys.extendUp.matches(event)   { model.extendSelectionUp(); return nil }
        if keys.extendDown.matches(event) { model.extendSelectionDown(); return nil }

        // ---- Search ----
        if config.search.matches(event) { model.activateSearch(); return nil }

        // ---- Single-selection-only actions (edit / label / paste) ----
        if keys.editText.matches(event) {
            if !model.hasMultiSelection, let item = model.selectedItem, item.isEditableText {
                model.editingText = item.text ?? ""; model.editingIndex = model.selection
            }
            return nil
        }
        if keys.label.matches(event) {
            if !model.hasMultiSelection, let item = model.selectedItem {
                model.labelText = item.label ?? ""; model.labelingIndex = model.selection
            }
            return nil
        }

        // ---- Multi-safe actions (copy to tab / delete) ----
        if keys.copyToTab.matches(event) {
            if store.tabs.count > 1, model.selectedItem != nil {
                model.copyToTabForIndex = model.selection
            }
            return nil
        }
        if keys.delete.matches(event) {
            let ids = model.hasMultiSelection ? model.selectedItems.map(\.id) : model.selectedItem.map { [$0.id] } ?? []
            if !ids.isEmpty { store.delete(ids, in: tabIndex); model.clampSelection() }
            return nil
        }

        // ---- Plain navigation (collapses multi-selection) ----
        if keys.selectUp.matches(event)   { model.moveSelectionUp(); return nil }
        if keys.selectDown.matches(event) { model.moveSelectionDown(); return nil }
        if keys.pageUp.matches(event)     { model.pageUp(by: config.ui.pageSize); return nil }
        if keys.pageDown.matches(event)   { model.pageDown(by: config.ui.pageSize); return nil }
        if keys.home.matches(event)       { model.moveSelectionToStart(); return nil }
        if keys.end.matches(event)        { model.moveSelectionToEnd(); return nil }
        if isCommit(event) {
            if model.hasMultiSelection { model.onCommitMany(model.selectedItems) }
            else { model.commit() }
            return nil
        }
        if isCancel(event) { handleEscape(); return nil }

        return event
    }

    /// Reorder the current selection (single or block) by delta and keep selection visible.
    private func reorder(by delta: Int) {
        if model.hasMultiSelection {
            let ids = model.selectedItems.map(\.id)
            store.moveMany(ids, in: tabIndex, by: delta)
            // Shift the tracked indices to follow the moved block.
            let f = model.filtered
            let idSet = Set(ids)
            let newIndices = Set(f.indices.filter { idSet.contains(f[$0].id) })
            model.selectedIndices = newIndices
            if let anchor = newIndices.min() { model.selectionAnchor = anchor }
            model.selection = delta < 0 ? (newIndices.min() ?? model.selection) : (newIndices.max() ?? model.selection)
        } else if let id = currentItemID {
            store.move(id, in: tabIndex, by: delta)
            if delta < 0 { model.moveSelectionUp() } else { model.moveSelectionDown() }
        }
    }

    private func handleEscape() {
        // If search is active, escape() collapses it; otherwise it hides + returns focus.
        if model.searchActive || model.isModalOpen {
            model.escape()
        } else {
            hideWindow(returnFocus: true)
        }
    }

    // MARK: Helpers

    /// Maps a filtered-list index to the underlying item id.
    private func itemID(at filteredIndex: Int) -> UUID? {
        let f = model.filtered
        return f.indices.contains(filteredIndex) ? f[filteredIndex].id : nil
    }

    /// If a number key 1-9 was pressed, return that tab index (0-based), else nil.
    private func tabNumberPressed(_ event: NSEvent) -> Int? {
        guard let chars = event.charactersIgnoringModifiers, let n = Int(chars), n >= 1 else { return nil }
        let idx = n - 1
        return store.tabs.indices.contains(idx) ? idx : nil
    }
}

/// A borderless panel that can still become key/main so text fields receive focus.
final class KeyablePanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
