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

**Most-recently-used ordering**
- Pasting an item from the clipboard tab moves it to the top, so the things you use most
  stay within reach. With a multi-selection, all pasted items move to the top preserving
  their relative order. Snippet tabs are never reordered by pasting — their order only
  changes when you reorder items manually. Set `copyPaste.promotePastedToTop` to `false`
  to keep the clipboard list order untouched too.

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
| **⇞ / ⇟** | Page selection up / down (jump by `ui.pageSize` rows) |
| **↖ / ↘** (Home / End) | Jump to the first / last item |
| **⏎** | Paste selected item(s) into the previous app |
| **⎋** | Close search, or close window and return focus to the previous app |
| **⌘F** | Open the search box (focused immediately) |
| **any letter / digit** | Starts searching right away (opens the search box and types into it) |
| **F2** | Edit item inline — text content, or the name of an image/file (single selection) |
| **F3** | Add / edit a label (single selection) |
| **F5** | Copy selection to another tab (then press the tab number) |
| **⌘D** | Download image link(s) — adds each linked image/GIF as a new item above its link |
| **⌘G** | Switch the current tab between list and tiles (remembered per tab) |
| **← / →** | Tiles: previous / next item (**↑ / ↓** move by a row, **⇧** extends) |
| **F8** | Delete selection |
| **⌘↑ / ⌘↓** | Reorder selection up / down within the list (disabled while searching) |
| **⌘← / ⌘→** | Switch between tabs |
| **⌘T** | New tab (prompts for a name) |
| **⌘R** | Rename the current tab (or double-click a tab) |
| **⌘W** | Remove the current tab (the auto-capture tab can't be removed) |
| **⌘Q** | Quit the app |

History persists between restarts. Captured images/files are stored as copies ("blobs")
in the storage folders described under [Storage layout & syncing](#storage-layout--syncing).

**List or tiles (⌘G)**
- Each tab can show its items as a list or as a grid of tiles (`ui.tileSize`, default
  150 pt — 4 per row in the default window). Images/GIFs fill their tile, text shows its
  first lines, and the caption is the label or name.
- The choice is saved per tab in `tabs.json` (`"layout": "tiles"`); tabs never switched use
  `ui.defaultLayout` (`"list"`).
- In tiles, **← / →** move between items, **↑ / ↓** by a row, **⇞ / ⇟** by a screen, and
  **⇧** + arrows extend the selection. Everything else (paste, F2, F3, F5, F8, ⌘D) is the same.

**Download images from links (⌘D)**
- Select one or more text items that are links to images or GIFs (e.g. a
  `https://media.tenor.com/….gif` link) and press **⌘D**. Each link is checked first (type
  and size, via a HEAD request); links that aren't images (e.g. web pages) are skipped.
- Images are downloaded in the background and added as a **new item directly above the
  link** — the link item itself stays. The file type comes from the downloaded bytes, the
  name from the link (e.g. `pepperidge-pepperidge-farm-remembers.gif`).
- Images larger than `imgDownloadLimitSize` (MB, default 40) are only downloaded after you
  confirm (Enter to download, Esc to skip).

**Large files are linked, not copied**
- Copying a file in Finder stores a copy of it — unless it's larger than `fileCopyLimitMB`
  (default 30 MB). Then the Clipboard tab only keeps a link (a bookmark that follows the
  file if it's moved or renamed), marked with a small 🔗 icon under the type badge.
- If the original is deleted (or moved to the Trash, or its drive is unplugged), the item
  turns grey with a ⚠︎ icon. It can still be selected, renamed, labelled and deleted, but
  not pasted. It comes back to normal if the file reappears.
- Pasting a linked item pastes the original file, just like Finder. If you renamed it with
  F2, a temporary copy under the new name is pasted instead.
- Snippet tabs always keep their own copy. Copying a linked item there (F5) first asks for
  confirmation, showing the size of the copy and the free disk space; the copy runs in the
  background.

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

### Window Manager
Move the focused window between displays with global hotkeys. Defaults:

| Key | Action |
|-----|--------|
| **⌃⌥→** | Move focused window to the next display |
| **⌃⌥←** | Move focused window to the previous display |
| **⌃⌥↑** | Maximize the focused window (fill the current display) |
| **⌃⌥↓** | Minimize the focused window to the Dock |
| **⌃⌥⌘←** | Snap the focused window to the left half of the current display |
| **⌃⌥⌘→** | Snap the focused window to the right half of the current display |

When moving between displays the window is **scaled proportionally** to the target
display's visible area (below the menu bar, clear of the Dock), keeping its relative
position and footprint. If the window is **maximized**, it stays maximized on the new
display (filling it, even if bigger). Displays are ordered left→right.

**Snap left/right** resizes the window to half the display and, in snap-assist style, pops
up a menu of other visible windows so you can pick one to fill the empty half. Press Escape
(or click away) to leave the other half empty.

Uses the **Accessibility** permission (the same one paste needs). All actions are also
available from the menu-bar menu. Configurable:

```json
{
  "windowManager": {
    "nextDisplay": { "key": "RIGHT", "modifiers": ["ctrl", "opt"] },
    "prevDisplay": { "key": "LEFT",  "modifiers": ["ctrl", "opt"] },
    "maximize":    { "key": "UP",    "modifiers": ["ctrl", "opt"] },
    "minimize":    { "key": "DOWN",  "modifiers": ["ctrl", "opt"] },
    "snapLeft":    { "key": "LEFT",  "modifiers": ["ctrl", "opt", "cmd"] },
    "snapRight":   { "key": "RIGHT", "modifiers": ["ctrl", "opt", "cmd"] }
  }
}
```

_Planned: alt-tab, half/quarter snapping._

## Requirements

- macOS 13+
- Xcode toolchain installed (`swift`, `xcodebuild`)
- **Accessibility permission** (for Enter-to-paste). The app prompts on first launch;
  grant it under System Settings → Privacy & Security → Accessibility. Run
  `./setup-signing.sh` once first so you only have to grant it once (see below).

## Build & install

**One-time: set up code signing.**

```bash
./setup-signing.sh
```

This creates a self-signed code-signing certificate named `mac-tools-signing` in your login
keychain. macOS ties the Accessibility grant to the app's code signature, so signing with a
stable identity means you grant Accessibility **once** instead of after every rebuild.
`install.sh` works without it, but falls back to ad-hoc signing and the permission is lost on
each install. The script is idempotent — re-running it is a no-op once the cert exists.

> On the first build after creating the cert, macOS asks for your keychain password. Click
> **Always Allow** (not just *Allow*) so later builds sign without prompting.

**Then, every time:**

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

## Tests

The window-manager geometry (display ordering, screen detection, coordinate flipping,
half-splitting, maximize detection, and proportional move/resize) is factored into a pure,
AppKit-free library target (`Sources/MacToolsGeometry/`) so it can be unit-tested without
real displays.

Because this machine has only the Command Line Tools (no full Xcode, so no `XCTest`), the
tests run through a tiny dependency-free harness:

```bash
swift run GeometryTests
```

It prints each check and exits non-zero on failure. The suite covers the real multi-display
layout, including the "don't skip the middle display" move cycle and proportional resizing.

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
    "maxHistory": 500,
    "pollInterval": 0.3,
    "clipboardPath": "~/Library/Caches/com.getoutreach.mac-tools/copy-paste",
    "snippetPath": "~/Library/Application Support/com.getoutreach.mac-tools/copy-paste",
    "tabsFile": "tabs.json",
    "clipboardFile": "clipboard.json",
    "fileCopyLimitMB": 30,
    "imgDownloadLimitSize": 40,
    "clipboardTabName": "Clipboard",
    "snippetTabs": ["Snippets", "Work"],
    "multiSelectPasteSeparator": "\n",
    "deleteTabConfirmWord": "delete",
    "promotePastedToTop": true,
    "showList": { "key": "L", "modifiers": ["cmd"] },
    "search":   { "key": "F", "modifiers": ["cmd"] },
    "window": { "width": 680, "height": 560, "floating": true, "hideOnClickAway": true, "followActiveDisplay": true },
    "ui": { "zebraStriping": true, "zebraOpacity": 0.05, "selectionOpacity": 0.22, "showFooterHints": true, "rowMaxLines": 10, "pageSize": 10, "animateGifs": "visible", "tileSize": 150, "defaultLayout": "list" },
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
      "pageUp":     { "key": "PAGEUP" },
      "pageDown":   { "key": "PAGEDOWN" },
      "home":       { "key": "HOME" },
      "end":        { "key": "END" },
      "prevTab":    { "key": "LEFT",  "modifiers": ["cmd"] },
      "nextTab":    { "key": "RIGHT", "modifiers": ["cmd"] },
      "newTab":     { "key": "T", "modifiers": ["cmd"] },
      "renameTab":  { "key": "R", "modifiers": ["cmd"] },
      "closeTab":   { "key": "W", "modifiers": ["cmd"] },
      "commit":     { "key": "RETURN" },
      "cancel":     { "key": "ESC" },
      "quit":       { "key": "Q", "modifiers": ["cmd"] },
      "downloadImage": { "key": "D", "modifiers": ["cmd"] },
      "toggleLayout": { "key": "G", "modifiers": ["cmd"] },
      "selectLeft":  { "key": "LEFT" },
      "selectRight": { "key": "RIGHT" },
      "extendLeft":  { "key": "LEFT",  "modifiers": ["shift"] },
      "extendRight": { "key": "RIGHT", "modifiers": ["shift"] }
    }
  }
}
```

- `key` — a letter, digit, function key (`F1`–`F12`), arrow (`UP`/`DOWN`/`LEFT`/`RIGHT`),
  or named key (`RETURN`, `ENTER`, `ESC`, `TAB`, `SPACE`, `DELETE`, `PAGEUP`, `PAGEDOWN`,
  `HOME`, `END`).
- `modifiers` — any of `cmd`, `shift`, `opt`, `ctrl`.
- `window.followActiveDisplay` — when `true` (default) the panel opens centered on the
  display you're working on (the one holding the focused window, else the one under the
  mouse). Set to `false` to always use the primary display.
- `ui.animateGifs` — GIF thumbnail animation: `"visible"` (default; rows on screen, only
  while the panel is shown), `"selected"` (only the highlighted row), or `"off"`.
  Animated thumbnails are small looping videos (HEVC with transparency) converted once per
  GIF in the background and cached in `~/Library/Caches/com.getoutreach.mac-tools/gif-video/`
  — the hardware video decoder plays them, so memory stays low. Pasting always uses the
  original GIF. Videos of GIFs no longer in any tab are removed at launch.
- `clipboardPath` / `snippetPath` — storage folders (see below). Absolute or `~` paths are
  used as-is; relative paths are resolved under the config dir. `tabsFile` /
  `clipboardFile` are file names inside those folders.
- Restart the app after editing.

### Storage layout & syncing

Copy-paste data lives in two folders, so the constantly-changing clipboard history stays
out of your backups and synced files:

| Folder | Default | Contains |
|---|---|---|
| `clipboardPath` | `~/Library/Caches/com.getoutreach.mac-tools/copy-paste` | `clipboard.json` + `blobs/` (copies of captured images/files ≤ `fileCopyLimitMB`) |
| `snippetPath` | `~/Library/Application Support/com.getoutreach.mac-tools/copy-paste` | `tabs.json` + `blobs/` (copies owned by snippet tabs) |

- **`tabsFile`** (default `tabs.json`) — all tabs and their names/order, plus your custom
  tab **items**, but with the auto-capture **Clipboard tab's items stripped out**. This
  file only changes when you edit tabs/snippets, so it's safe to **symlink into a synced
  dotfiles repo** (or point `snippetPath` at a synced folder).
- **`clipboardFile`** (default `clipboard.json`) — only the volatile clipboard history.
  Changes on every copy. Caches isn't backed up by Time Machine; if the folder is cleaned,
  history starts fresh (items whose copy vanished show as missing).

Blob files are named `<UUID>.<ext>`; the JSON maps each item to its blob. Files no item
references are deleted at launch.

JSON is written with **sorted keys**, so editing one value produces a minimal, stable diff
instead of the whole file appearing to change.

**Upgrading:** on first launch, data from the old single-folder layout
(`<configDir>/copy-paste/` with one shared `blobs/`) is moved into the two folders
automatically — each item's file goes to the folder of its tab. To keep snippets where they
were, set `"snippetPath": "~/.config/mac-tools/copy-paste"`. Older `tabs.json` files that
still embed clipboard items are split into `clipboardFile` too.

## Architecture

Each tool implements the `Feature` protocol and is registered in `buildFeatures()` in
`main.swift`. Shared infrastructure lives in `Core/`.

```
Package.swift                        SPM manifest
install.sh                           build + bundle + sign + install-to-~/Applications
setup-signing.sh                     one-time: self-signed cert for a stable signature
Sources/MacTools/
  main.swift                         app delegate, shared status-bar menu, feature registry
  Core/
    Feature.swift                    Feature protocol + menu contribution
    AppConfig.swift                  top-level config (one section per feature)
    AppPaths.swift                   ~/.config/mac-tools paths
    Shortcut.swift                   JSON shortcut model + key/modifier mapping
    HotKey.swift                     multi-hotkey Carbon registration
    ActiveScreen.swift               resolves the display that currently has focus
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
