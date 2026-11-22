# Notecast

An ultra-lightweight, single-process native macOS floating Markdown scratchpad built with Swift 6, AppKit, and Carbon `RegisterEventHotKey` — zero Electron/WebViews, zero helper processes, and no Accessibility permissions required.

## Download

Download the latest Apple Silicon (`.dmg` or `.zip`) build directly from [GitHub Releases](https://github.com/sekhar-88/notecast/releases/latest):

1. Open `Notecast-v*-arm64.dmg` and drag **Notecast** into **Applications** (or unzip `Notecast-v*-arm64.zip`).
2. Because this release is ad-hoc signed rather than Apple Developer notarized, if macOS Gatekeeper blocks the first open, clear the quarantine attribute once:

```bash
xattr -cr /Applications/Notecast.app
```

## Features

- **Instant Global Hotkey** (`⌥⌘N` by default, configurable in Settings) — always opens back into the note view on the last note you were working on
- **12 Background Themes & Active Neon Glow**: choose directly from a visual color swatch palette in Settings — **Charcoal** (default), **Graphite**, **Pure Black**, **Midnight Slate**, **Deep Indigo**, **Nordic Blue**, **Warm Espresso**, **Deep Forest**, **Plum Noir**, **Warm Paper**, **Cool Mist**, or **Translucent HUD**, paired with a luminous neon edge glow when focused (Cyan, Violet, Magenta, Emerald, or Amber)
- **Ghost Outline Mode (Optional)**: turn transparent when unfocused — hiding all text while keeping a high-contrast dual-tone reticle outline (visible on both light and dark backgrounds), a fully click-through left 55%, and a subtly shaded click-to-wake right 45% zone
- **Always-On-Top Floating Panel**: stays above other apps and full-screen Spaces while windows underneath remain interactable
- **Multi-Note Library & Built-In Search / Command Palette**:
  - `⌘P` opens the Raycast-style search & command palette (search notes or type `>` for commands)
  - `⌘⇧P` opens **Notes-Only Search** to jump directly between notes
  - `⌘N` creates a new note
  - `⌘L` opens the notes list to switch or delete notes
- **Selectable Apple & System Fonts (with Live Preview)**: choose System (SF Pro), SF Pro Rounded, New York (Serif), SF Mono, Avenir Next, Menlo, Georgia, or any installed macOS font family, previewing live as you navigate with `↑`/`↓` in the font picker, with full word wrap and `⌘+` / `⌘-` / `⌘0` sizing
- **Live Markdown Styling & Smart Editing**: headings (`#`–`####`), **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `` `inline code` ``, `> blockquotes`, auto-continuing lists, and clickable `- [ ]` / `- [x]` checklists
- **Atomic Persistence & Size Memory**: remembers window position and resized dimensions, and saves each note atomically under `~/Library/Application Support/Notecast/notes/`

## Keyboard Shortcuts

### Global & In-Window Navigation

| Shortcut | Action |
| :--- | :--- |
| `⌥⌘N` (configurable) | Show / hide Notecast |
| `⌘P` | Search notes & run commands |
| `⌘⇧P` | Search notes only |
| `⌘N` | Create a new note |
| `⌘L` | Show / hide notes list |
| `Esc` | Dismiss palette or notes list |
| `⌘,` | Open Settings |

### Markdown Editing & View

| Shortcut | Action |
| :--- | :--- |
| `⌘B` | Bold (`**text**`) |
| `⌘I` | Italic (`*text*`) |
| `⌘E` | Inline code (`` `code` ``) |
| `⌘⇧X` | Strikethrough (`~~text~~`) |
| `⌘↩` or `⌘⇧L` | Toggle checklist (`- [ ]` ↔ `- [x]`) |
| `Tab` / `⇧Tab` | Indent / outdent list items or selection |
| `⌘+` / `⌘-` / `⌘0` | Increase / decrease / reset font size |

## Build & Run

Requires macOS 14+ (Apple Silicon / Universal) and Swift 6 (Xcode Command Line Tools).

```bash
# Run unit tests
swift test

# Build release .app bundle at build/Notecast.app
./scripts/build-app.sh

# Build and install directly into /Applications/Notecast.app
./scripts/build-app.sh --install
```

Launch the app:

```bash
open build/Notecast.app
```

## Notes Storage

Notes are stored as individual UTF-8 Markdown files (`<uuid>.md`) alongside a lightweight `index.json` manifest in:

```text
~/Library/Application Support/Notecast/notes/
```

## License

Copyright © 2026 Chandrasekhar Sahoo. All rights reserved.

You may download and run the official release builds for personal use. Copying, modifying, redistributing, or using the source code or binaries commercially without explicit permission is not permitted.
