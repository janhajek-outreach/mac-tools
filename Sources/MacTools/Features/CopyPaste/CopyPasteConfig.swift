import Foundation

/// All copy-paste settings, fully JSON-configurable. Any value omitted from
/// config.json falls back to the corresponding value in `.default`.
struct CopyPasteConfig: Codable {
    // Global hotkeys
    var showList: Shortcut
    var search: Shortcut

    // In-panel key bindings (matched against local key events while the panel is open)
    var keys: KeyBindings

    // Storage
    var maxHistory: Int
    /// How often (seconds) to poll the pasteboard for new items.
    var pollInterval: Double
    /// Directory (relative to the feature data dir, or absolute/`~`) where image/file blobs live.
    var blobDir: String
    /// Filename (within the feature data dir) for the persisted tabs — everything EXCEPT the
    /// auto-capture clipboard items (safe to sync / symlink).
    var tabsFile: String
    /// Filename (within the feature data dir) for the volatile clipboard-tab items
    /// (changes constantly; intentionally kept separate so it need not be synced).
    var clipboardFile: String

    // Tabs
    /// Name of the fixed auto-capture tab.
    var clipboardTabName: String
    /// Names of the snippet tabs created on first run (in addition to the clipboard tab).
    var snippetTabs: [String]

    // Window / UI
    var window: WindowConfig
    var ui: UIConfig

    // Behavior
    /// Separator inserted between items when pasting a multi-selection of text items.
    var multiSelectPasteSeparator: String
    /// Word the user must type to confirm deleting a non-empty tab.
    var deleteTabConfirmWord: String

    struct KeyBindings: Codable {
        var editText: Shortcut          // inline edit (text only)
        var label: Shortcut             // add/edit label
        var copyToTab: Shortcut         // copy selection to another tab
        var delete: Shortcut            // delete selection
        var moveUp: Shortcut            // reorder selection up
        var moveDown: Shortcut          // reorder selection down
        var selectUp: Shortcut          // move selection up (extends with shift)
        var selectDown: Shortcut        // move selection down (extends with shift)
        var extendUp: Shortcut          // extend selection up
        var extendDown: Shortcut        // extend selection down
        var prevTab: Shortcut
        var nextTab: Shortcut
        var newTab: Shortcut
        var renameTab: Shortcut
        var closeTab: Shortcut
        var commit: Shortcut            // paste
        var cancel: Shortcut            // escape / close
        var quit: Shortcut

        init(
            editText: Shortcut, label: Shortcut, copyToTab: Shortcut, delete: Shortcut,
            moveUp: Shortcut, moveDown: Shortcut, selectUp: Shortcut, selectDown: Shortcut,
            extendUp: Shortcut, extendDown: Shortcut, prevTab: Shortcut, nextTab: Shortcut,
            newTab: Shortcut, renameTab: Shortcut, closeTab: Shortcut,
            commit: Shortcut, cancel: Shortcut, quit: Shortcut
        ) {
            self.editText = editText; self.label = label; self.copyToTab = copyToTab
            self.delete = delete; self.moveUp = moveUp; self.moveDown = moveDown
            self.selectUp = selectUp; self.selectDown = selectDown
            self.extendUp = extendUp; self.extendDown = extendDown
            self.prevTab = prevTab; self.nextTab = nextTab; self.newTab = newTab
            self.renameTab = renameTab; self.closeTab = closeTab
            self.commit = commit; self.cancel = cancel; self.quit = quit
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = CopyPasteConfig.default.keys
            func g(_ key: CodingKeys, _ fallback: Shortcut) -> Shortcut {
                (try? c.decode(Shortcut.self, forKey: key)) ?? fallback
            }
            editText = g(.editText, d.editText); label = g(.label, d.label)
            copyToTab = g(.copyToTab, d.copyToTab); delete = g(.delete, d.delete)
            moveUp = g(.moveUp, d.moveUp); moveDown = g(.moveDown, d.moveDown)
            selectUp = g(.selectUp, d.selectUp); selectDown = g(.selectDown, d.selectDown)
            extendUp = g(.extendUp, d.extendUp); extendDown = g(.extendDown, d.extendDown)
            prevTab = g(.prevTab, d.prevTab); nextTab = g(.nextTab, d.nextTab)
            newTab = g(.newTab, d.newTab); renameTab = g(.renameTab, d.renameTab)
            closeTab = g(.closeTab, d.closeTab); commit = g(.commit, d.commit)
            cancel = g(.cancel, d.cancel); quit = g(.quit, d.quit)
        }
    }

    struct WindowConfig: Codable {
        var width: Double
        var height: Double
        var floating: Bool
        var hideOnClickAway: Bool

        init(width: Double, height: Double, floating: Bool, hideOnClickAway: Bool) {
            self.width = width; self.height = height
            self.floating = floating; self.hideOnClickAway = hideOnClickAway
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = CopyPasteConfig.default.window
            width = (try? c.decode(Double.self, forKey: .width)) ?? d.width
            height = (try? c.decode(Double.self, forKey: .height)) ?? d.height
            floating = (try? c.decode(Bool.self, forKey: .floating)) ?? d.floating
            hideOnClickAway = (try? c.decode(Bool.self, forKey: .hideOnClickAway)) ?? d.hideOnClickAway
        }
    }

    struct UIConfig: Codable {
        var zebraStriping: Bool
        var zebraOpacity: Double
        var selectionOpacity: Double
        var showFooterHints: Bool
        /// Max number of text lines a row expands to before being visually truncated.
        var rowMaxLines: Int

        init(zebraStriping: Bool, zebraOpacity: Double, selectionOpacity: Double, showFooterHints: Bool, rowMaxLines: Int) {
            self.zebraStriping = zebraStriping; self.zebraOpacity = zebraOpacity
            self.selectionOpacity = selectionOpacity; self.showFooterHints = showFooterHints
            self.rowMaxLines = rowMaxLines
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = CopyPasteConfig.default.ui
            zebraStriping = (try? c.decode(Bool.self, forKey: .zebraStriping)) ?? d.zebraStriping
            zebraOpacity = (try? c.decode(Double.self, forKey: .zebraOpacity)) ?? d.zebraOpacity
            selectionOpacity = (try? c.decode(Double.self, forKey: .selectionOpacity)) ?? d.selectionOpacity
            showFooterHints = (try? c.decode(Bool.self, forKey: .showFooterHints)) ?? d.showFooterHints
            rowMaxLines = (try? c.decode(Int.self, forKey: .rowMaxLines)) ?? d.rowMaxLines
        }
    }

    // Per-field fallback: any missing key uses the default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CopyPasteConfig.default
        showList  = (try? c.decode(Shortcut.self, forKey: .showList)) ?? d.showList
        search    = (try? c.decode(Shortcut.self, forKey: .search)) ?? d.search
        keys      = (try? c.decode(KeyBindings.self, forKey: .keys)) ?? d.keys
        maxHistory = (try? c.decode(Int.self, forKey: .maxHistory)) ?? d.maxHistory
        pollInterval = (try? c.decode(Double.self, forKey: .pollInterval)) ?? d.pollInterval
        blobDir   = (try? c.decode(String.self, forKey: .blobDir)) ?? d.blobDir
        tabsFile  = (try? c.decode(String.self, forKey: .tabsFile)) ?? d.tabsFile
        clipboardFile = (try? c.decode(String.self, forKey: .clipboardFile)) ?? d.clipboardFile
        clipboardTabName = (try? c.decode(String.self, forKey: .clipboardTabName)) ?? d.clipboardTabName
        snippetTabs = (try? c.decode([String].self, forKey: .snippetTabs)) ?? d.snippetTabs
        window    = (try? c.decode(WindowConfig.self, forKey: .window)) ?? d.window
        ui        = (try? c.decode(UIConfig.self, forKey: .ui)) ?? d.ui
        multiSelectPasteSeparator = (try? c.decode(String.self, forKey: .multiSelectPasteSeparator)) ?? d.multiSelectPasteSeparator
        deleteTabConfirmWord = (try? c.decode(String.self, forKey: .deleteTabConfirmWord)) ?? d.deleteTabConfirmWord
    }

    // Memberwise initializer (retained because we added a custom decoder).
    init(
        showList: Shortcut, search: Shortcut, keys: KeyBindings, maxHistory: Int,
        blobDir: String, tabsFile: String, clipboardFile: String, clipboardTabName: String, snippetTabs: [String],
        window: WindowConfig, ui: UIConfig, multiSelectPasteSeparator: String, deleteTabConfirmWord: String,
        pollInterval: Double
    ) {
        self.showList = showList; self.search = search; self.keys = keys
        self.maxHistory = maxHistory; self.blobDir = blobDir; self.tabsFile = tabsFile
        self.clipboardFile = clipboardFile
        self.clipboardTabName = clipboardTabName; self.snippetTabs = snippetTabs
        self.window = window; self.ui = ui
        self.multiSelectPasteSeparator = multiSelectPasteSeparator
        self.deleteTabConfirmWord = deleteTabConfirmWord
        self.pollInterval = pollInterval
    }

    static let `default` = CopyPasteConfig(
        showList: Shortcut(key: "L", modifiers: ["cmd"]),
        search: Shortcut(key: "F", modifiers: ["cmd"]),
        keys: KeyBindings(
            editText:   Shortcut(key: "F2"),
            label:      Shortcut(key: "F3"),
            copyToTab:  Shortcut(key: "F5"),
            delete:     Shortcut(key: "F8"),
            moveUp:     Shortcut(key: "UP", modifiers: ["cmd"]),
            moveDown:   Shortcut(key: "DOWN", modifiers: ["cmd"]),
            selectUp:   Shortcut(key: "UP"),
            selectDown: Shortcut(key: "DOWN"),
            extendUp:   Shortcut(key: "UP", modifiers: ["shift"]),
            extendDown: Shortcut(key: "DOWN", modifiers: ["shift"]),
            prevTab:    Shortcut(key: "LEFT", modifiers: ["cmd"]),
            nextTab:    Shortcut(key: "RIGHT", modifiers: ["cmd"]),
            newTab:     Shortcut(key: "T", modifiers: ["cmd"]),
            renameTab:  Shortcut(key: "R", modifiers: ["cmd"]),
            closeTab:   Shortcut(key: "W", modifiers: ["cmd"]),
            commit:     Shortcut(key: "RETURN"),
            cancel:     Shortcut(key: "ESC"),
            quit:       Shortcut(key: "Q", modifiers: ["cmd"])
        ),
        maxHistory: 200,
        blobDir: "blobs",
        tabsFile: "tabs.json",
        clipboardFile: "clipboard.json",
        clipboardTabName: "Clipboard",
        snippetTabs: ["Snippets", "Work"],
        window: WindowConfig(width: 680, height: 560, floating: true, hideOnClickAway: true),
        ui: UIConfig(zebraStriping: true, zebraOpacity: 0.05, selectionOpacity: 0.22, showFooterHints: true, rowMaxLines: 10),
        multiSelectPasteSeparator: "\n",
        deleteTabConfirmWord: "delete",
        pollInterval: 0.3
    )
}
