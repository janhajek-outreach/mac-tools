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
    /// The exact window that had focus when the panel opened, so we can raise just that one.
    private var previousWindow: AXUIElement?

    init(config: CopyPasteConfig) {
        self.config = config
        // Resolve storage folders, move data over from the old single-folder layout, then
        // point the blob stores at the configured folders before loading.
        let clipboardDir = CopyPasteFeature.resolveDir(config.clipboardPath)
        let snippetDir = CopyPasteFeature.resolveDir(config.snippetPath)
        let migrated = CopyPasteStorage.migrateLegacyLayout(
            legacyDir: AppPaths.configDir.appendingPathComponent("copy-paste", isDirectory: true),
            clipboardDir: clipboardDir,
            snippetDir: snippetDir,
            clipboardFile: config.clipboardFile,
            tabsFile: config.tabsFile
        )
        BlobStore.configure(
            clipboard: clipboardDir.appendingPathComponent("blobs", isDirectory: true),
            snippets: snippetDir.appendingPathComponent("blobs", isDirectory: true)
        )
        self.store = TabStore(
            maxHistory: config.maxHistory,
            snippetTabNames: config.snippetTabs,
            clipboardTabName: config.clipboardTabName,
            tabsFileURL: snippetDir.appendingPathComponent(config.tabsFile),
            clipboardFileURL: clipboardDir.appendingPathComponent(config.clipboardFile),
            cleanOrphanBlobs: migrated
        )
        self.model = PickerModel(store: store)
        super.init()
    }

    /// Absolute or `~` paths are used as-is; relative ones resolve under the config dir.
    private static func resolveDir(_ path: String) -> URL {
        if path.hasPrefix("/") || path.hasPrefix("~") { return AppPaths.expand(path) }
        return AppPaths.configDir.appendingPathComponent(path, isDirectory: true)
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
        store.defaultLayout = TabLayout(rawValue: config.ui.defaultLayout.lowercased()) ?? .list
        model.columns = TileMetrics.columns(width: config.window.width, tile: config.ui.tileSize)
        model.pageRows = TileMetrics.rowsPerPage(height: config.window.height, tile: config.ui.tileSize)
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
        ClipboardMonitor.fileCopyLimitBytes = Int64(max(0, config.fileCopyLimitMB)) * 1024 * 1024
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
        previousWindow = ActiveScreen.focusedWindow(of: previousApp)
        model.reset()
        store.refreshReferences()
        positionOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.isVisible = true
        installLocalKeyMonitor()
    }

    /// Center the panel on the display the user is actually working on (the one holding the
    /// focused window, else the one under the mouse) rather than always the primary display.
    private func positionOnActiveScreen() {
        guard config.window.followActiveDisplay else { return }
        let size = CGSize(width: config.window.width, height: config.window.height)
        guard let frame = ActiveScreen.centeredFrame(size: size, holding: previousWindow) else { return }
        window.setFrame(frame, display: false)
    }

    /// Return focus to exactly the window the user came from.
    ///
    /// We deliberately avoid `.activateAllWindows`: that raises *every* window of the target app,
    /// so pasting into (say) a browser window on one display would also yank that browser's
    /// windows on other displays above whatever the user had in front there.
    private func restorePreviousFocus() {
        if let win = previousWindow {
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        previousApp?.activate()
        previousWindow = nil
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
        model.isVisible = false
        if returnFocus { restorePreviousFocus() } else { previousWindow = nil }
    }

    private func pasteAndHide(_ item: ClipItem) {
        // Image/file items paste from disk — refuse (and mark grey) if the file is gone.
        var fileURL: URL?
        if item.kind != .text {
            fileURL = store.locateFile(for: item, inTab: store.currentTab)
            guard fileURL != nil else {
                NSSound.beep()
                model.flash("File is missing — can't paste")
                return
            }
        }

        // Most-recently-used ordering: the item we just pasted moves to the top of its tab.
        promoteToTop([item])

        // Put the content on the clipboard first.
        Paster.setClipboard(item, fileURL: fileURL)
        monitor.syncChangeCount()

        // If we can't post key events, just hand off the clipboard and let the user paste.
        guard Paster.ensureAccessibilityPermission(prompt: false) else {
            hideWindow(returnFocus: true)
            Paster.warnAccessibilityMissing()
            return
        }

        // Hide our window and refocus the window we came from before pasting into it.
        removeLocalKeyMonitor()
        window.orderOut(nil)
        model.isVisible = false
        restorePreviousFocus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Paster.simulatePaste()
        }
    }

    /// Paste multiple text items joined by the configured separator.
    private func pasteManyAndHide(_ items: [ClipItem]) {
        let texts = items.compactMap { $0.kind == .text ? $0.text : nil }
        guard !texts.isEmpty else { hideWindow(returnFocus: true); return }
        promoteToTop(items)
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
        model.isVisible = false
        restorePreviousFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Paster.simulatePaste()
        }
    }

    /// Move the pasted items to the top of the clipboard tab, and keep the picker's
    /// selection pointing at the (now top-most) rows. Snippet tabs keep their manual order.
    private func promoteToTop(_ items: [ClipItem]) {
        guard config.promotePastedToTop, !items.isEmpty,
              store.currentTab == store.clipboardTabIndex else { return }
        store.promoteToTop(items.map(\.id), in: store.currentTab)
        model.selectSingle(0)
        if items.count > 1 { model.selectedIndices = Set(0..<items.count) }
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
                let f = model.filtered
                if let editIdx = model.editingIndex, f.indices.contains(editIdx) {
                    let item = f[editIdx]
                    if item.kind == .text {
                        store.setText(model.editingText, for: item.id, in: tabIndex)
                    } else {
                        store.setName(model.editingText, for: item.id, in: tabIndex)
                    }
                }
                model.editingIndex = nil
                return nil
            }
            if isCancel(event) { model.editingIndex = nil; return nil }
            return event
        }

        // ---- Modal: confirm downloading images over the size limit (⌘D) ----
        if let pending = model.pendingDownload {
            if isCommit(event) {
                model.pendingDownload = nil
                downloadConfirmed(pending)
                return nil
            }
            if isCancel(event) {
                model.pendingDownload = nil
                pending.candidates.forEach { downloadsInFlight.remove(downloadKey(pending.tabID, $0.url)) }
                model.flash("Skipped \(pending.candidates.count) large image(s)")
                return nil
            }
            return nil
        }

        // ---- Modal: confirm copying large linked files into another tab ----
        if let pending = model.pendingCopy {
            if isCommit(event) {
                if pending.hasEnoughSpace {
                    model.pendingCopy = nil
                    performCopy(pending.ids, from: pending.sourceTab, to: pending.destTab)
                } else {
                    NSSound.beep()
                }
                return nil
            }
            if isCancel(event) { model.pendingCopy = nil; return nil }
            return nil
        }

        // ---- Modal: copy-to-tab picker ----
        if let srcIndex = model.copyToTabForIndex {
            if isCancel(event) { model.copyToTabForIndex = nil; return nil }
            if let dest = tabNumberPressed(event), dest != store.currentTab {
                // Copy all selected items if multi-selected, else just the source row.
                let items = model.hasMultiSelection
                    ? model.selectedItems
                    : (model.filtered.indices.contains(srcIndex) ? [model.filtered[srcIndex]] : [])
                model.copyToTabForIndex = nil
                requestCopy(items, to: dest)
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
        if model.isTiles, !model.searchActive {
            if keys.extendUp.matches(event)    { model.moveInGrid(by: -model.columns, extend: true); return nil }
            if keys.extendDown.matches(event)  { model.moveInGrid(by: model.columns, extend: true); return nil }
            if keys.extendLeft.matches(event)  { model.moveInGrid(by: -1, extend: true); return nil }
            if keys.extendRight.matches(event) { model.moveInGrid(by: 1, extend: true); return nil }
        }
        if keys.extendUp.matches(event)   { model.extendSelectionUp(); return nil }
        if keys.extendDown.matches(event) { model.extendSelectionDown(); return nil }

        // ---- Search ----
        if config.search.matches(event) { model.activateSearch(); return nil }

        // ---- Single-selection-only actions (edit / label / paste) ----
        if keys.editText.matches(event) {
            if !model.hasMultiSelection, let item = model.selectedItem {
                model.editingText = item.editableValue; model.editingIndex = model.selection
            }
            return nil
        }
        if keys.label.matches(event) {
            if !model.hasMultiSelection, let item = model.selectedItem {
                model.labelText = item.label ?? ""; model.labelingIndex = model.selection
            }
            return nil
        }

        // ---- Multi-safe actions (copy to tab / delete / download images) ----
        if keys.toggleLayout.matches(event) {
            store.toggleLayout(ofTab: store.currentTab)
            return nil
        }
        if keys.downloadImage.matches(event) {
            downloadSelectedImages()
            return nil
        }
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
        if model.isTiles {
            let page = model.columns * model.pageRows
            if keys.selectUp.matches(event)   { model.moveInGrid(by: -model.columns); return nil }
            if keys.selectDown.matches(event) { model.moveInGrid(by: model.columns); return nil }
            if !model.searchActive {
                // In the search box ←/→ keep moving the text cursor.
                if keys.selectLeft.matches(event)  { model.moveInGrid(by: -1); return nil }
                if keys.selectRight.matches(event) { model.moveInGrid(by: 1); return nil }
            }
            if keys.pageUp.matches(event)   { model.pageUp(by: page); return nil }
            if keys.pageDown.matches(event) { model.pageDown(by: page); return nil }
        }
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

        // ---- Type-to-search: any plain letter/digit starts filtering immediately ----
        if !model.searchActive, let typed = typedSearchCharacter(event) {
            model.activateSearch()
            model.query.append(typed)
            model.selectSingle(0)
            return nil
        }

        return event
    }

    /// Returns the character to seed the search box with when the user just starts typing
    /// (plain a-z / A-Z / 0-9, optionally with shift — never with cmd/ctrl/opt).
    private func typedSearchCharacter(_ event: NSEvent) -> Character? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.contains(.command), !mods.contains(.control),
              !mods.contains(.option), !mods.contains(.function) else { return nil }
        guard let chars = event.characters, chars.count == 1, let c = chars.first else { return nil }
        guard c.isLetter || c.isNumber else { return nil }
        return c
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
            // Follow the moved row; reordering never wraps, so clamp rather than wrap.
            let last = max(0, model.filtered.count - 1)
            model.selectSingle(min(max(0, model.selection + delta), last))
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

    // MARK: Download images from links (⌘D)

    /// Links currently being probed/downloaded (or awaiting confirmation), per tab.
    private var downloadsInFlight = Set<String>()

    private func downloadKey(_ tabID: UUID, _ url: URL) -> String {
        "\(tabID.uuidString) \(url.absoluteString)"
    }

    /// For every selected text item that is a link: check it's an image (HEAD), download it
    /// and add it as a new item above the link (the link item stays). Non-image links are
    /// skipped; images over `imgDownloadLimitSize` are downloaded only after confirmation.
    private func downloadSelectedImages() {
        let tab = store.currentTab
        guard store.tabs.indices.contains(tab) else { return }
        let tabID = store.tabs[tab].id
        let selected = model.hasMultiSelection ? model.selectedItems : (model.selectedItem.map { [$0] } ?? [])
        var links: [(id: UUID, url: URL)] = []
        for item in selected where item.kind == .text {
            if let url = ImageDownloader.link(in: item.text), !downloadsInFlight.contains(downloadKey(tabID, url)) {
                links.append((item.id, url))
            }
        }
        guard !links.isEmpty else {
            NSSound.beep()
            model.flash(selected.count > 1 ? "No image links selected" : "Not a link")
            return
        }
        links.forEach { downloadsInFlight.insert(downloadKey(tabID, $0.url)) }
        var skipped = selected.count - links.count
        let limit = Int64(max(1, config.imgDownloadLimitSize)) * 1024 * 1024
        model.flash(links.count == 1 ? "Checking link…" : "Checking \(links.count) links…")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let probes = await withTaskGroup(of: (Int, ImageDownloader.Probe).self) { group in
                for (i, link) in links.enumerated() {
                    group.addTask { (i, await ImageDownloader.probe(link.url)) }
                }
                var out = [ImageDownloader.Probe](repeating: .failed(""), count: links.count)
                for await (i, probe) in group { out[i] = probe }
                return out
            }

            var within: [PickerModel.DownloadCandidate] = []
            var over: [PickerModel.DownloadCandidate] = []
            for (i, probe) in probes.enumerated() {
                let link = links[i]
                guard case .candidate(let size) = probe else {
                    skipped += 1
                    self.downloadsInFlight.remove(self.downloadKey(tabID, link.url))
                    continue
                }
                let candidate = PickerModel.DownloadCandidate(sourceID: link.id, url: link.url, size: size)
                if let size, size > limit { over.append(candidate) } else { within.append(candidate) }
            }

            if !within.isEmpty {
                self.model.flash(within.count == 1 ? "Downloading image…" : "Downloading \(within.count) images…")
            }
            // Unknown sizes are capped at the limit; those that turn out bigger join `over`.
            let result = await self.download(within, tabID: tabID, cap: limit)
            skipped += result.skipped
            over += result.tooLarge

            self.model.flash(self.downloadSummary(added: result.added, skipped: skipped))
            if !over.isEmpty { self.askToDownload(over, tabID: tabID, limit: limit) }
        }
    }

    private func askToDownload(_ candidates: [PickerModel.DownloadCandidate], tabID: UUID, limit: Int64) {
        if let existing = model.pendingDownload, existing.tabID == tabID {
            model.pendingDownload = PickerModel.PendingDownload(
                candidates: existing.candidates + candidates, tabID: tabID, limitBytes: limit)
        } else {
            model.pendingDownload?.candidates.forEach {
                downloadsInFlight.remove(downloadKey(model.pendingDownload!.tabID, $0.url))
            }
            model.pendingDownload = PickerModel.PendingDownload(candidates: candidates, tabID: tabID, limitBytes: limit)
        }
    }

    private func downloadConfirmed(_ pending: PickerModel.PendingDownload) {
        model.flash(pending.candidates.count == 1 ? "Downloading image…" : "Downloading \(pending.candidates.count) images…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.download(pending.candidates, tabID: pending.tabID, cap: nil)
            self.model.flash(self.downloadSummary(added: result.added, skipped: result.skipped))
        }
    }

    /// Download candidates concurrently and insert each image above its link as it arrives.
    @MainActor
    private func download(_ candidates: [PickerModel.DownloadCandidate], tabID: UUID, cap: Int64?)
        async -> (added: Int, skipped: Int, tooLarge: [PickerModel.DownloadCandidate]) {
        await withTaskGroup(of: (PickerModel.DownloadCandidate, ImageDownloader.Download).self) { group in
            for c in candidates {
                group.addTask { (c, await ImageDownloader.download(c.url, cap: cap)) }
            }
            var added = 0, skipped = 0
            var tooLarge: [PickerModel.DownloadCandidate] = []
            for await (c, result) in group {
                switch result {
                case .image(let file, let ext):
                    let name = ImageDownloader.name(for: c.url, ext: ext)
                    if store.insertDownloadedImage(file: file, ext: ext, name: name, aboveItem: c.sourceID, inTabID: tabID) {
                        added += 1
                    } else {
                        skipped += 1
                    }
                    downloadsInFlight.remove(downloadKey(tabID, c.url))
                case .tooLarge:
                    tooLarge.append(c) // stays "in flight" until confirmed or skipped
                case .notImage, .failed:
                    skipped += 1
                    downloadsInFlight.remove(downloadKey(tabID, c.url))
                }
            }
            return (added, skipped, tooLarge)
        }
    }

    private func downloadSummary(added: Int, skipped: Int) -> String {
        var parts: [String] = []
        if added > 0 { parts.append(added == 1 ? "Added 1 image" : "Added \(added) images") }
        if skipped > 0 { parts.append("skipped \(skipped) (not an image or failed)") }
        return parts.isEmpty ? "Nothing downloaded" : parts.joined(separator: ", ")
    }

    // MARK: Copy to tab

    /// Copy items to another tab. Missing linked items are skipped; if any linked originals
    /// will be materialized into full copies, ask first (showing the size and free space).
    private func requestCopy(_ items: [ClipItem], to dest: Int) {
        let source = store.currentTab
        var copyable: [ClipItem] = []
        var skipped = 0
        var linkedBytes: Int64 = 0
        var linkedCount = 0
        for item in items {
            guard item.kind != .text else { copyable.append(item); continue }
            guard let url = store.locateFile(for: item, inTab: source) else { skipped += 1; continue }
            copyable.append(item)
            if item.isReference {
                linkedCount += 1
                linkedBytes += FileReference.size(of: url) ?? 0
            }
        }

        if copyable.isEmpty {
            NSSound.beep()
            model.flash(skipped == 1 ? "File no longer exists — nothing to copy" : "Files no longer exist — nothing to copy")
            return
        }
        if skipped > 0 { model.flash("Skipped \(skipped) missing file(s)") }

        let ids = copyable.map(\.id)
        guard linkedCount > 0 else {
            performCopy(ids, from: source, to: dest)
            return
        }
        model.pendingCopy = PickerModel.PendingCopy(
            ids: ids,
            sourceTab: source,
            destTab: dest,
            destName: store.tabs.indices.contains(dest) ? store.tabs[dest].name : "tab",
            itemCount: linkedCount,
            bytes: linkedBytes,
            freeBytes: FileReference.freeSpace(at: store.blobDir(forTab: dest).dir)
        )
    }

    private func performCopy(_ ids: [UUID], from source: Int, to dest: Int) {
        store.copyItems(ids, from: source, to: dest) { [weak self] failed in
            if failed > 0 { self?.model.flash("\(failed) item(s) couldn't be copied") }
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
