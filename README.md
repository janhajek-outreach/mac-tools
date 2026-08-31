# mac-tools

A single macOS menu-bar app that hosts a collection of personal utilities. One running
app, multiple tools. The first tool is a CopyQ-style clipboard manager; more (window
management, screenshots, alt-tab, …) will be added as `Feature`s over time.

## Tools

### Copy Paste (clipboard manager)
Captures everything you copy (text, images, files) and lets you pick, edit, label, pin,
and organise entries across tabs — then paste into whatever app you were using.

**Content types**
- **Text**, **images** (with thumbnails in the list), and **files** (zip, docs, anything).

**Tabs**
- The first tab, **Clipboard**, auto-captures your copy history (newest first, capped).
- Additional tabs (configurable, default **Snippets** / **Work**) hold saved snippets.
- **⌘← / ⌘→** — switch tabs.

**Tabs**
- The first tab (default name **Clipboard**) auto-captures your copy history (newest first, capped).
- Additional tabs (configurable, default **Snippets** / **Work**) hold saved snippets.
- Add / rename / remove tabs at runtime (see keys below). Non-empty tabs require typing a
  confirmation word (default `delete`) before removal.

**Multi-select**
- Hold **⇧** with the select-up/down keys (or shift-click a row) to select a range.
- With more than one item selected, only **copy-to-tab**, **reorder**, **delete**, and
  **paste** work. Paste joins the selected text items with a configurable separator
  (default newline); non-text items are skipped. A plain up/down collapses back to one item.

**Keys (defaults — all remappable in config.json)**
| Key | Action |
|-----|--------|
| **⌘L** | Show / hide the picker (global) |
| **↑ / ↓** | Move selection (collapses a multi-selection) |
| **⇧↑ / ⇧↓** | Extend the selection range |
| **⏎** | Paste selected item(s) into the previous app |
| **⎋** | Close search, or close window and return focus to the previous app |
| **⌘F** | Search (type to filter) |
| **F2** | Edit item inline (plain text only; single selection) |
| **F3** | Add / edit a label (single selection) |
| **F5** | Copy selection to another tab (then press the tab number) |
| **F8** | Delete selection |
| **⌘↑ / ⌘↓** | Reorder selection up / down within the list (disabled while searching) |
| **⌘← / ⌘→** | Switch between tabs |
| **⌘T** | New tab (prompts for a name) |
| **⌘R** | Rename the current tab (or double-click a tab) |
| **⌘W** | Remove the current tab (the auto-capture tab can't be removed) |
| **⌘Q** | Quit the app |

History persists between restarts. Images/files are stored as blobs under the configured
blob directory (default `copy-paste/blobs/` inside the config dir).

### Screenshot
Interactive rectangle capture. Press the hotkey (default **⌥F12**, configurable via
`screenshot.capture`) to get macOS's native crosshair selection; the captured PNG is
copied to the clipboard, and the copy-paste tool auto-captures it into the **Clipboard**
tab with a thumbnail. Requires **Screen Recording** permission (System Settings → Privacy
& Security → Screen Recording) — grant it once if screenshots come out blank.

The capture command and its arguments are configurable, so you can swap in a different
tool or flags (default is `screencapture -i -c`):

```json
{
  "screenshot": {
    "capture":   { "key": "F12", "modifiers": ["opt"] },
    "command":   "/usr/sbin/screencapture",
    "arguments": ["-i", "-c"]
  }
}
```

_Planned: window management, alt-tab._

## Requirements

- macOS 13+
- Xcode toolchain installed (`swift`, `xcodebuild`)
- **Accessibility permission** (for Enter-to-paste). The app prompts on first launch;
  grant it under System Settings → Privacy & Security → Accessibility.

## Build & install

```bash
./install.sh              # build + sign + install to ~/Applications + relaunch
./install.sh --no-launch  # build + sign + install only (don't quit/relaunch)
```

`install.sh` builds the app, signs it, copies it into **`~/Applications/MacTools.app`**
(the standard place for a personal app — no admin password needed), quits any running
instance, and relaunches the installed copy. The menu-bar icon (default 🧰, set via
`app.menuBarTitle`) appears in the menu bar.

**Start at login** — pick the menu-bar icon → **Start at Login** to toggle it (uses
`SMAppService`, so no manual System Settings step). You can also default it on by setting
`"app": { "launchAtLogin": true }` in `config.json`; it's applied at startup. Because the
login item points at `~/Applications/MacTools.app`, keep installing there for it to stay valid.

> Moved the project directory? Run `rm -rf .build` first — SPM bakes absolute paths into its cache.

## Configuration

Everything is configurable via JSON — no hardcoded shortcuts, paths, or sizes. Config lives
at `~/.config/mac-tools/config.json` (created with full defaults on first run). Any key you
omit falls back to its built-in default, so you only need to specify what you want to change.

**Overriding the config directory**
- `MAC_TOOLS_CONFIG_DIR` environment variable (highest priority), or
- `app.configDir` in the JSON (absolute or `~`-relative).

```json
{
  "app": {
    "menuBarTitle": "🧰",
    "configDir": "~/.config/mac-tools",
    "launchAtLogin": false
  },
  "copyPaste": {
    "maxHistory": 200,
    "pollInterval": 0.3,
    "blobDir": "blobs",
    "tabsFile": "tabs.json",
    "clipboardFile": "clipboard.json",
    "clipboardTabName": "Clipboard",
    "snippetTabs": ["Snippets", "Work"],
    "multiSelectPasteSeparator": "\n",
    "deleteTabConfirmWord": "delete",
    "showList": { "key": "L", "modifiers": ["cmd"] },
    "search":   { "key": "F", "modifiers": ["cmd"] },
    "window": { "width": 680, "height": 560, "floating": true, "hideOnClickAway": true },
    "ui": { "zebraStriping": true, "zebraOpacity": 0.05, "selectionOpacity": 0.22, "showFooterHints": true },
    "keys": {
      "editText":   { "key": "F2" },
      "label":      { "key": "F3" },
      "copyToTab":  { "key": "F5" },
      "delete":     { "key": "F8" },
      "moveUp":     { "key": "UP",    "modifiers": ["cmd"] },
      "moveDown":   { "key": "DOWN",  "modifiers": ["cmd"] },
      "selectUp":   { "key": "UP" },
      "selectDown": { "key": "DOWN" },
      "extendUp":   { "key": "UP",    "modifiers": ["shift"] },
      "extendDown": { "key": "DOWN",  "modifiers": ["shift"] },
      "prevTab":    { "key": "LEFT",  "modifiers": ["cmd"] },
      "nextTab":    { "key": "RIGHT", "modifiers": ["cmd"] },
      "newTab":     { "key": "T", "modifiers": ["cmd"] },
      "renameTab":  { "key": "R", "modifiers": ["cmd"] },
      "closeTab":   { "key": "W", "modifiers": ["cmd"] },
      "commit":     { "key": "RETURN" },
      "cancel":     { "key": "ESC" },
      "quit":       { "key": "Q", "modifiers": ["cmd"] }
    }
  }
}
```

- `key` — a letter, digit, function key (`F1`–`F12`), arrow (`UP`/`DOWN`/`LEFT`/`RIGHT`),
  or named key (`RETURN`, `ENTER`, `ESC`, `TAB`, `SPACE`, `DELETE`).
- `modifiers` — any of `cmd`, `shift`, `opt`, `ctrl`.
- `blobDir` / `tabsFile` / `clipboardFile` — relative paths are resolved under the
  copy-paste data dir; absolute or `~` paths are used as-is.
- Restart the app after editing.

### Storage layout & syncing

Copy-paste persistence is split into two files so you can sync your snippets without the
constantly-changing clipboard history creating noise:

- **`tabsFile`** (default `tabs.json`) — all tabs and their names/order, plus your custom
  tab **items**, but with the auto-capture **Clipboard tab's items stripped out**. This
  file only changes when you edit tabs/snippets, so it's safe to **symlink into a synced
  dotfiles repo**.
- **`clipboardFile`** (default `clipboard.json`) — only the volatile clipboard history.
  Changes on every copy; keep it local (not synced).

JSON is written with **sorted keys**, so editing one value produces a minimal, stable diff
instead of the whole file appearing to change. Blob bytes for images/files live under
`blobDir`. On first launch after upgrading, any clipboard items still embedded in an old
`tabs.json` are migrated automatically into `clipboardFile`.

## Architecture

Each tool implements the `Feature` protocol and is registered in `buildFeatures()` in
`main.swift`. Shared infrastructure lives in `Core/`.

```
Package.swift                        SPM manifest
install.sh                           build + bundle + sign + install-to-~/Applications
Sources/MacTools/
  main.swift                         app delegate, shared status-bar menu, feature registry
  Core/
    Feature.swift                    Feature protocol + menu contribution
    AppConfig.swift                  top-level config (one section per feature)
    AppPaths.swift                   ~/.config/mac-tools paths
    Shortcut.swift                   JSON shortcut model + key/modifier mapping
    HotKey.swift                     multi-hotkey Carbon registration
  Features/
    CopyPaste/
      CopyPasteFeature.swift         window, hotkey, key routing, paste
      CopyPasteConfig.swift          copy-paste config section
      ClipItem.swift                 item model (text/image/file, pin, label)
      TabStore.swift                 tabs, items, pin/move/delete/label, persistence
      BlobStore.swift                on-disk storage for image/file bytes
      ClipboardMonitor.swift         captures text/image/file from the pasteboard
      Paster.swift                   clipboard write (any type) + simulated ⌘V
      PickerModel.swift              observable UI state (selection, search, edit, modals)
      PanelView.swift                SwiftUI picker: tabs, thumbnails, inline edit, labels
```

### Adding a new tool
1. Create `Sources/MacTools/Features/<Name>/<Name>Feature.swift` implementing `Feature`.
2. Add its config section to `AppConfig` (if it needs config).
3. Append it to `buildFeatures()` in `main.swift`.
