# Notecast

An ultra-lightweight, single-process native macOS floating Markdown scratchpad built with Swift 6, AppKit, and Carbon `RegisterEventHotKey` — zero Electron/WebViews, zero helper processes, and no Accessibility permissions required.

## Features

- **Instant Global Hotkey** (`⌥ Space` by default, configurable in Settings) — always opens back into the note view on the last note you were working on
- **Curated Background Themes & Active Neon Glow**: choose from **Charcoal (Opaque, default)**, **Midnight Slate**, **Warm Espresso**, **Deep Forest**, **Pure Black**, **Warm Paper (Light)**, or **Translucent HUD**, paired with a luminous neon edge glow when focused (Cyan, Violet, Magenta, Emerald, or Amber)
- **Always-On-Top Floating Panel**: stays above other apps and full-screen Spaces while windows underneath remain interactable
- **Multi-Note Library & Built-In Search / Command Palette**:
  - `⌘P` opens the Raycast-style search & command palette (search notes or type `>` for commands)
  - `⌘⇧P` opens **Notes-Only Search** to jump directly between notes
  - `⌘N` creates a new note
  - `⌘L` opens the notes list to switch or delete notes
- **Selectable Apple & System Fonts**: choose System (SF Pro), SF Pro Rounded, New York (Serif), SF Mono, Avenir Next, Menlo, Georgia, or any installed macOS font family, with full word wrap and `⌘+` / `⌘-` / `⌘0` sizing
- **Live Markdown Styling & Smart Editing**: headings (`#`–`####`), **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `` `inline code` ``, `> blockquotes`, auto-continuing lists, and clickable `- [ ]` / `- [x]` checklists
- **Atomic Persistence & Size Memory**: remembers window position and resized dimensions, and saves each note atomically under `~/Library/Application Support/Notecast/notes/`

## Keyboard Shortcuts

### Global & In-Window Navigation

| Shortcut | Action |
| :--- | :--- |
| `⌥ Space` (configurable) | Show / hide Notecast |
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
