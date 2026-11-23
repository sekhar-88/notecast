# Notecast for Windows — Architecture, Feature Parity & Store Plan

This document captures all research, product specifications, architecture decisions, and Microsoft Store publishing notes for building the **Windows 11 counterpart of Notecast** (targeting full parity with macOS Notecast **v0.4.1**).

> **Note:** This file is intended as a portable handoff guide for continuing development on a Windows machine after cloning this repository. It is **not** bundled into macOS release artifacts (`scripts/package-release.sh` packages only `build/Notecast.app`).

---

## 1. Product Goal & Core Principles

Build an ultra-lightweight, fast, native-feeling **Windows 11 floating Markdown scratchpad** published under **Quakeship** on the **Microsoft Store**:

- **Minimal memory & package footprint** — no Electron, no bloated background helper services.
- **Instant muscle-memory UX** — one global hotkey shows/hides the floating panel immediately on the last edited note.
- **Data safety first** — plain UTF-8 `.md` files with **atomic writes**, external-edit protection, and bounded memory caches.
- **Clean security posture** — packaged as a Microsoft-signed **`.msix`** via Microsoft Store so SmartScreen and endpoint security (e.g., Defender / SentinelOne) treat it as a trusted signed Store app rather than an unsigned hotkey utility.

---

## 2. Feature Parity Specification (Matching macOS v0.4.1)

Reference the macOS source files in this repo for exact edge-case behavior:
- `Sources/NotecastCore/AppSettings.swift` — themes, accents, checkbox styles, settings clamping
- `Sources/NotecastCore/MarkdownStyler.swift` — Markdown parsing, fenced code blocks, link detection, list/checkbox styling
- `Sources/NotecastCore/MarkdownListHelper.swift` — auto-continue, Roman numerals, column-0 Enter guard, atomic Backspace, `-- ` divider
- `Sources/NotecastCore/NoteStore.swift` — atomic file I/O, `index.json`, revision checks, rollback-safe delete, bounded caches
- `Sources/Notecast/FloatingNotepadPanel.swift` & `PanelChromeViews.swift` — Ghost Mode, wake zone, neon glow, grip pill
- `Sources/Notecast/MarkdownLayoutManager.swift` — custom vector checkboxes, bullets, blockquote bars, code cards, dividers

### 2.1 Windowing, Hotkeys & System Tray
- **Always-on-top floating panel** (`WS_EX_TOPMOST`), excluded from Alt+Tab clutter (`WS_EX_TOOLWINDOW` or tray-owned utility window), remembers last position and resized dimensions (clamped to active monitor work area on wake/restore).
- **Global toggle hotkey**: `Ctrl+Alt+N` default on Windows (user-configurable in Settings via Win32 `RegisterHotKey`).
  - Preserve global/local Settings shortcut (`Ctrl+Alt+,` / `Ctrl+,`) when recording a new toggle hotkey and reject shortcut collisions.
- **System tray icon**: quick actions for Show/Hide, New Note, Settings, Launch at Startup (`StartupTask` in MSIX manifest), and Quit.
- **Follow all virtual desktops** (optional setting, using Windows Virtual Desktop API / pinned window behavior where supported).

### 2.2 Ghost Outline Mode (Optional)
- When unfocused (and enabled), the panel turns transparent, hiding note text while displaying a **dual-tone corner reticle outline** visible on both light and dark wallpapers/apps.
- **Configurable Wake Zone** (`15%–100%`, default `45%` on the right side):
  - **Left zone (`1 - wakeZoneFraction`)**: true OS-level click-through to underlying windows.
  - **Right zone (`wakeZoneFraction`)**: subtly shaded click-to-wake area.
- **Draggable grip pill**: allows repositioning the ghosted window without waking it.
- **Off-screen frame clamping**: disabling Ghost Mode or waking restores/clamps the window safely inside visible monitors.

### 2.3 Visual Themes, Active Neon Glow & Independent UI Accents

#### 12 Background Surface Themes
| Theme | Background | Header | Palette Card | Light Mode? |
| :--- | :--- | :--- | :--- | :--- |
| **Charcoal** *(default)* | `#141519` | `#1B1D24` | `#191B22` (98%) | No |
| **Graphite** | `#22242A` | `#2B2E36` | `#262930` (98%) | No |
| **Pure Black** | `#000000` | `#08080C` | `#0B0B10` (98%) | No |
| **Midnight Slate** | `#171C26` | `#1E2533` | `#1B212E` (98%) | No |
| **Deep Indigo** | `#19172B` | `#221F38` | `#1E1B33` (98%) | No |
| **Nordic Blue** | `#1D2733` | `#253140` | `#212C3A` (98%) | No |
| **Warm Espresso** | `#1A1715` | `#221E1B` | `#1F1B18` (98%) | No |
| **Deep Forest** | `#121A17` | `#18231F` | `#16201C` (98%) | No |
| **Plum Noir** | `#1F1520` | `#2A1D2B` | `#251926` (98%) | No |
| **Warm Paper** | `#F7F5F0` | `#EFECE4` | `#FBF9F5` (98%) | Yes |
| **Cool Mist** | `#EEF2F6` | `#E3E9F0` | `#F5F8FB` (98%) | Yes |
| **Translucent HUD** | Windows 11 Acrylic / Mica backdrop | Native tint | System translucent card | Adapts |

- **Window Opacity**: `65%–100%` (default `96%`).
- **Active Neon Glow** (enabled by default, toggled independently from UI Accent):
  - **Neon Cyan** `#00F0FF`, **Neon Violet** `#B84DFF`, **Neon Magenta** `#FF2E97`, **Neon Emerald** `#00FF9D`, **Neon Amber** `#FFB800`.
  - Renders crisp border + subtle inner/outer glow only when window is focused; falls back to calm border (`rgba(255,255,255,0.14)` on dark / `rgba(0,0,0,0.14)` on light) when unfocused.
- **Independent UI Accent** (drives checkboxes, blockquote bars, links, active buttons, and caret — completely separate from Neon Glow):
  - 8 options: **Cyan**, **Violet**, **Magenta**, **Emerald**, **Amber**, **Coral**, **Sky Blue**, **Windows System Accent**.
  - Automatically uses darker high-contrast shades on light surfaces (`Warm Paper`, `Cool Mist`) — see `UIAccent.effectiveColor(forLightSurface:)` in `AppSettings.swift`.
- **Checkbox Shape** setting: **Circle** *(default)* or **Rounded Square**.
- **Selectable Fonts**: curated Windows defaults (`Segoe UI Variable`, `Segoe UI`, `Cascadia Code`, `Consolas`, `Georgia`, `Calibri`) + any installed system font with live preview, full word wrap, and `11pt–26pt` sizing (default `14pt`).

### 2.4 Bear-Style Live Markdown Editor & Smart Editing
- **Inline & block styling**:
  - Headings (`#`–`####`), **bold** (`**text**`), *italic* (`*text*`), ***bold italic***, ~~strikethrough~~ (`~~text~~`), `` `inline code` ``.
  - Blockquotes (`> `) with vertical accent bar.
  - Fenced code blocks (```` ``` ````) with rounded card background, monospace font, incremental restyling on fence open/close/delete, and smart-list suppression inside fences.
  - Horizontal dividers: typing `-- ` (double hyphen + Space) converts to `---\n` and renders as a clean full-width separator line.
- **Interactive Checklists (`- [ ]` / `- [x]`)**:
  - Custom vector Circle / Rounded Square rendering in a fixed-width slot so toggling checked state causes **zero horizontal text shift**.
  - Generous spacing between checkbox and label text; reliable hit-testing on both single clicks and rapid multi-clicks (never selects hidden markdown characters behind the checkbox).
  - Checked rows dim and strikethrough text cleanly.
- **Lists**:
  - **Bullets**: `- ` + Space or `Ctrl+Shift+8` → solid circular bullet dot (hollow ring when indented/nested).
  - **Numbered**: `1. ` + Space or `Ctrl+Shift+9` → tabular digits, auto-incrementing on `Enter`.
  - **Roman numerals**: `i. `, `ii. `, `iii. `, `iv. ` (and uppercase `I. `, `II. `, …) → canonical Roman auto-increment on `Enter`.
  - **List ergonomics**:
    - Pressing `Enter` on an empty list item exits the list cleanly.
    - Column-0 / inside-prefix `Enter` protection (never splits `- [ ]` or leaks stray hyphens).
    - Atomic `Backspace` removes the entire list/checkbox prefix cleanly.
    - `Tab` / `Shift+Tab` indents/outdents single lines or multi-line selections.
- **Links & Input Safety**:
  - `Ctrl`-click opens URLs (supporting balanced parentheses like Wikipedia URLs and short local URLs).
  - Plain-text-only `Copy` / `Cut` (never copies rich attributed styling onto clipboard).
  - IME composition guards (do not trigger autosave or smart-list mutations mid-IME composition).
  - Multi-selection safety (pass through cleanly without corrupting ranges).

### 2.5 Multi-Note Library, Palette & Shortcuts (Windows Mapping)
| Windows Shortcut | Action |
| :--- | :--- |
| `Ctrl+Alt+N` *(configurable)* | Show / hide Notecast globally |
| `Ctrl+P` | Search notes & run commands (`>` prefix) |
| `Ctrl+Shift+P` | Search notes only |
| `Ctrl+N` | Create new note |
| `Ctrl+L` | Toggle notes list (switch / delete) |
| `Ctrl+,` | Open Settings |
| `Esc` | Dismiss palette or notes list |
| `Ctrl+B` / `Ctrl+I` / `Ctrl+E` | Bold / Italic / Inline code |
| `Ctrl+Shift+X` | Strikethrough |
| `Ctrl+Enter` or `Ctrl+Shift+L` | Toggle checklist (`- [ ]` ↔ `- [x]`) |
| `Ctrl+Shift+8` / `Ctrl+Shift+9` | Toggle bullet / numbered list |
| `Tab` / `Shift+Tab` | Indent / outdent |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+0` | Increase / decrease / reset font size |

### 2.6 Persistence & Data Safety Requirements
- Store notes as individual UTF-8 Markdown files (`<uuid>.md`) + compact `index.json` manifest under:
  ```text
  %LOCALAPPDATA%\Notecast\notes\
  ```
- **Atomic writes**: write to `<file>.tmp` in the same directory, flush to disk, then atomically replace target (`File.Replace` / `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH`).
- **External-edit safety**: track file revision `(fileIndex/lastWriteUtc/byteLength)` + `isEditorDirty` flag. Never let an unedited buffer overwrite external `.md` changes; refresh cleanly when re-showing the panel.
- **Failure resilience**:
  - Preserve pending dirty edits per note ID (`pendingByID`) when switching notes.
  - Rollback-safe note deletion (stage-delete before updating `index.json`; preserve active note buffer if deleting an inactive note).
  - Open unreadable note files in read-only warning mode rather than overwriting them with empty text.
  - Prompt with a save-failure warning dialog on app shutdown if flushing dirty notes fails.
- **Memory efficiency**: cap in-memory note body cache (~16 MB) and palette search cache (~8 MB FIFO), with O(1) early-exit title/preview extraction.

---

## 3. Windows Tech Stack Decision

Now that development will continue directly on a **Windows laptop**, we can test native Windows UI and Win32 behavior live with zero VM overhead.

### Recommended Stack: **C# / .NET 8 (or .NET 9) + WPF + Win32 P/Invoke**
Why **WPF (.NET 8/9)** is the strongest fit for Notecast on Windows:
1. **Lowest RAM & single-process feel**: ~20–30 MB idle RAM, zero WebView2/Chromium subprocesses, instant startup.
2. **Pixel-exact split Ghost Mode**: Win32 `WM_NCHITTEST` (returning `HTTRANSPARENT` on the left `1 - wakeZoneFraction` and `HTCLIENT` on the right `wakeZoneFraction`) gives true partial-window click-through identical to macOS `NSWindow`, plus crisp per-pixel alpha transparency for the neon border glow and dual-tone ghost reticle.
3. **Full Win32 access**: clean P/Invoke for `RegisterHotKey`, `WS_EX_TOPMOST`, `WS_EX_TOOLWINDOW`, `DwmSetWindowAttribute` (Windows 11 rounded corners + Mica/Acrylic), and system tray (`NotifyIcon`).
4. **First-class MSIX packaging**: builds directly into a Microsoft Store `.msix` / `.msixbundle` via Visual Studio / `dotnet publish` / Windows Application Packaging Project (or `makeappx.exe` in GitHub Actions `windows-latest`).
5. **Custom Bear-style Markdown editor**: either a tailored WPF `AvalonEdit` / `FlowDocument` / custom DirectWrite-backed editor layer that keeps raw Markdown as the single source of truth while drawing custom vector checkboxes, bullets, code cards, and horizontal rules (mirroring our macOS `MarkdownStyler` + `MarkdownLayoutManager` architecture).

### Alternative Stack: **Tauri v2 (Rust + WebView2)**
Consider only if you strongly prefer web CSS + CodeMirror 6 for fastest rich-Markdown UI styling:
- **Pros**: ~4–6 MB `.msix` (uses built-in Windows 11 WebView2), rapid Bear-style editor implementation with CodeMirror 6 decorations/widgets, shared Rust core (`notecast-core`).
- **Cons**: ~45–60 MB RAM (WebView2 renderer process), and partial-width Ghost Mode still requires custom Win32 `WM_NCHITTEST` subclassing on the HWND.

### Proposed Repository Layout (Sibling Repo `notecast-windows`)
Keep the Windows codebase in its own repository (e.g., `sekhar-88/notecast-windows`) so macOS SwiftPM and Windows .NET/MSIX build toolchains stay clean and independent:

```text
notecast-windows/
├── Notecast.sln
├── src/
│   ├── Notecast.Core/              # Pure C# logic (NoteStore, MarkdownParser, ListHelper, Settings)
│   ├── Notecast.App/               # WPF floating window, Ghost Mode, Neon Chrome, Editor, Tray
│   └── Notecast.Package/           # MSIX Windows Application Packaging Project + Store visual assets
├── tests/
│   └── Notecast.Core.Tests/        # xUnit tests porting all 61 macOS core test cases
└── .github/
    └── workflows/
        └── build-msix.yml          # Automated windows-latest CI build + test + MSIX packaging
```

---

## 4. Microsoft Store Distribution & Security Notes

### Quakeship Account Status
- **Microsoft Store Company developer account** for **Quakeship** is already created and verified via `https://storedeveloper.microsoft.com` (**\$0 registration fee**, unlimited apps, free Microsoft `.msix` signing).
- **Publisher Display Name**: `Quakeship`
- **Website**: https://quakeship.com
- **Privacy Policy URL**: https://quakeship.com/privacy
- **Public Support Email**: `support@quakeship.com`

### Why Microsoft Store `.msix` Matters for Enterprise / AV Environments
- Unsigned sideloaded `.exe` apps that register global hotkeys (`RegisterHotKey`), stay always-on-top, and auto-start are frequent triggers for Windows SmartScreen and corporate EDR (e.g., SentinelOne / Microsoft Defender for Endpoint).
- Publishing as a Store **`.msix`**:
  - Microsoft signs the final package with Microsoft's official Store certificate.
  - Passes Microsoft Store automated certification and malware checks.
  - Avoids SmartScreen warnings and dramatically reduces EDR false positives. *(Note: corporate IT/MDM can still audit installed Store apps even when EDR does not flag them.)*
- **Safe Testing Workflow**: Use **Partner Center → Package Flights (Private Audience)** restricted to your Microsoft Account so even pre-release test builds are Microsoft-signed and installed cleanly via the Microsoft Store app.

### Store Submission Checklist (When Ready)
1. In **Partner Center → Apps and games**, click **Create a new app** and reserve the name **`Notecast`**.
2. Open **Product management → Product identity** and copy:
   - **Package/Identity/Name** (e.g., `Quakeship.Notecast` or Partner Center-assigned identity)
   - **Package/Identity/Publisher** (`CN=<from-partner-center>`)
   - **Package/Properties/PublisherDisplayName** (`Quakeship`)
3. Generate Windows Store PNG assets (`Square44x44Logo`, `Square150x150Logo`, `Wide310x150Logo`, `StoreLogo`, target-size badge icons) from the existing macOS icon artwork in `Assets/`.
4. Set `Privacy Policy` to `https://quakeship.com/privacy` and complete the EU DSA trader declaration if distributing in EEA.
5. **Monetization**:
   - **Free v1**: no payout or tax profile required — publish immediately.
   - **Future Paid / Pro Unlock**: prefer **Free core + One-time Pro unlock** (MS Store Add-on / IAP) over hard paywalls or ads; complete W-8BEN + tax ID + business current account before enabling paid listings.

---

## 5. Step-by-Step Build Milestones (On Windows Laptop)

1. **Phase 1 — Core Engine & Unit Tests (`Notecast.Core`)**
   - Port atomic `NoteStore`, `index.json`, `FileRevision`, bounded caches, `AppSettings`, `MarkdownListHelper` (checkboxes, bullets, numbers, Roman numerals, `-- ` divider), and port all 61 unit tests from macOS `Tests/NotecastCoreTests`.
2. **Phase 2 — Floating Window, Tray, Hotkey & Ghost Mode (`Notecast.App`)**
   - Borderless rounded Windows 11 floating panel, `RegisterHotKey`, system tray, 12 themes + Translucent HUD (Acrylic/Mica), Active Neon Glow, and split click-through Ghost Mode via `WM_NCHITTEST` + draggable wake grip.
3. **Phase 3 — Bear-Style Markdown Editor & Palette**
   - Live Markdown rendering, custom Circle/Square vector checkboxes with zero jitter, bullet/numbered/Roman lists, fenced code cards, blockquote bars, horizontal dividers, `Ctrl+P` / `Ctrl+Shift+P` search & command palette, `Ctrl+L` notes list, and Settings window.
4. **Phase 4 — MSIX Packaging, Private Flight & Microsoft Store Release**
   - Build `.msix` / `.msixbundle`, run Windows App Certification Kit (WACK), test via **Partner Center Private Flight**, then submit `Notecast v1.0.0` publicly under **Quakeship**.
