# mac-tools

A single macOS menu-bar app that hosts a collection of personal utilities. One running
app, multiple tools. The first tool is a CopyQ-style clipboard manager; more (window
management, screenshots, alt-tab, …) will be added as `Feature`s over time.

## Tools

### Copy Paste (clipboard manager)
- **Automatic clipboard history** — every text you copy (⌘C in any app) is stored, newest first.
- **⌘L** — bring up the picker window from anywhere.
- **↑ / ↓ / Enter** — navigate the numbered list and paste the selection into the app you were in.
- **⌘F** — search: type to filter the list.
- **Esc** — clear search, then close.
- History persists between restarts and is capped (default 200 entries).

_Planned: window management, screenshots, alt-tab._

## Requirements

- macOS 13+
- Xcode toolchain installed (`swift`, `xcodebuild`)
- **Accessibility permission** (for Enter-to-paste). The app prompts on first launch;
  grant it under System Settings → Privacy & Security → Accessibility.

## Build & run

```bash
./build.sh          # compiles + assembles MacTools.app + ad-hoc signs it
open MacTools.app   # launch it
```

The 🧰 icon appears in the menu bar.

> Moved the project directory? Run `rm -rf .build` first — SPM bakes absolute paths into its cache.

## Configuration

Config lives at `~/.config/mac-tools/config.json` (created on first run), one section per tool:

```json
{
  "copyPaste": {
    "maxHistory": 200,
    "showList": { "key": "L", "modifiers": ["cmd"] },
    "search":   { "key": "F", "modifiers": ["cmd"] }
  }
}
```

- `key` — a single letter or digit.
- `modifiers` — any of `cmd`, `shift`, `opt`, `ctrl`.
- Restart the app after editing.

Per-tool data lives under `~/.config/mac-tools/<tool>/` (e.g. `copy-paste/history.json`).

## Architecture

Each tool implements the `Feature` protocol and is registered in `buildFeatures()` in
`main.swift`. Shared infrastructure lives in `Core/`.

```
Package.swift                        SPM manifest
build.sh                             build + bundle + sign script
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
      HistoryStore.swift             persistent, observable clipboard history
      ClipboardMonitor.swift         polls NSPasteboard.changeCount
      Paster.swift                   clipboard write + simulated ⌘V
      PanelView.swift                SwiftUI picker UI + PickerModel
```

### Adding a new tool
1. Create `Sources/MacTools/Features/<Name>/<Name>Feature.swift` implementing `Feature`.
2. Add its config section to `AppConfig` (if it needs config).
3. Append it to `buildFeatures()` in `main.swift`.
