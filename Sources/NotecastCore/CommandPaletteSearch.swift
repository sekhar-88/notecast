import Foundation

/// Identifiers for built-in commands available from the `⌘P` search & command palette.
public enum AppCommandID: String, CaseIterable, Sendable {
    case newNote
    case showNotesList
    case toggleImmersiveBlack
    case toggleNeonGlow
    case cycleNeonAccent
    case toggleAlwaysOnTop
    case toggleFollowSpaces
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
    case deleteCurrentNote
    case revealNotesFolder
    case openSettings
}

/// Metadata describing an executable command in the command palette.
public struct AppCommandDescriptor: Equatable, Sendable {
    public let id: AppCommandID
    public let title: String
    public let subtitle: String
    public let shortcut: String
    public let symbolName: String
    public let keywords: [String]

    public init(
        id: AppCommandID,
        title: String,
        subtitle: String,
        shortcut: String,
        symbolName: String,
        keywords: [String]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.symbolName = symbolName
        self.keywords = keywords
    }

    public static let all: [AppCommandDescriptor] = [
        AppCommandDescriptor(
            id: .newNote,
            title: "New Note",
            subtitle: "Create a blank Markdown note",
            shortcut: "⌘N",
            symbolName: "square.and.pencil",
            keywords: ["create", "add", "blank", "scratchpad"]
        ),
        AppCommandDescriptor(
            id: .showNotesList,
            title: "Show Notes List",
            subtitle: "Browse, switch, or delete saved notes",
            shortcut: "⌘L",
            symbolName: "list.bullet",
            keywords: ["notes", "browse", "switch", "history", "list"]
        ),
        AppCommandDescriptor(
            id: .toggleImmersiveBlack,
            title: "Toggle Immersive Black / Translucent HUD",
            subtitle: "Switch between opaque black and translucent HUD",
            shortcut: "",
            symbolName: "circle.lefthalf.filled",
            keywords: ["opaque", "black", "dark", "theme", "surface", "hud", "transparent"]
        ),
        AppCommandDescriptor(
            id: .toggleNeonGlow,
            title: "Toggle Active Neon Glow",
            subtitle: "Enable or disable luminous border when focused",
            shortcut: "",
            symbolName: "sparkles",
            keywords: ["neon", "glow", "border", "highlight", "active"]
        ),
        AppCommandDescriptor(
            id: .cycleNeonAccent,
            title: "Cycle Neon Accent Color",
            subtitle: "Switch between Cyan, Violet, Magenta, Emerald, and Amber",
            shortcut: "",
            symbolName: "paintpalette",
            keywords: ["neon", "color", "accent", "cyan", "violet", "magenta", "emerald", "amber"]
        ),
        AppCommandDescriptor(
            id: .toggleAlwaysOnTop,
            title: "Toggle Always on Top",
            subtitle: "Pin or unpin the floating window above other apps",
            shortcut: "",
            symbolName: "pin",
            keywords: ["pin", "float", "top", "level"]
        ),
        AppCommandDescriptor(
            id: .toggleFollowSpaces,
            title: "Toggle Follow All Spaces",
            subtitle: "Show across all Desktop Spaces and full-screen apps",
            shortcut: "",
            symbolName: "macwindow.on.rectangle",
            keywords: ["spaces", "fullscreen", "desktops", "all"]
        ),
        AppCommandDescriptor(
            id: .increaseFontSize,
            title: "Increase Font Size",
            subtitle: "Make editor text larger",
            shortcut: "⌘+",
            symbolName: "textformat.size.larger",
            keywords: ["zoom", "bigger", "text", "font"]
        ),
        AppCommandDescriptor(
            id: .decreaseFontSize,
            title: "Decrease Font Size",
            subtitle: "Make editor text smaller",
            shortcut: "⌘-",
            symbolName: "textformat.size.smaller",
            keywords: ["zoom", "smaller", "text", "font"]
        ),
        AppCommandDescriptor(
            id: .resetFontSize,
            title: "Reset Font Size",
            subtitle: "Restore default 14 pt editor size",
            shortcut: "⌘0",
            symbolName: "textformat.size",
            keywords: ["zoom", "default", "text", "font"]
        ),
        AppCommandDescriptor(
            id: .deleteCurrentNote,
            title: "Delete Current Note",
            subtitle: "Remove the active note from disk",
            shortcut: "",
            symbolName: "trash",
            keywords: ["remove", "discard", "delete"]
        ),
        AppCommandDescriptor(
            id: .revealNotesFolder,
            title: "Reveal Notes Folder in Finder",
            subtitle: "Open the local Markdown notes directory",
            shortcut: "",
            symbolName: "folder",
            keywords: ["finder", "files", "storage", "markdown", "export"]
        ),
        AppCommandDescriptor(
            id: .openSettings,
            title: "Open Settings",
            subtitle: "Configure hotkey, font, surface, and neon accent",
            shortcut: "⌘,",
            symbolName: "gearshape",
            keywords: ["preferences", "hotkey", "font", "config", "options"]
        )
    ]
}

/// Unified entry shown in the `⌘P` search & command palette.
public enum PaletteEntry: Equatable, Sendable {
    case note(NoteMetadata)
    case command(AppCommandDescriptor)
}

/// Pure filtering and ranking logic for the `⌘P` search & command palette.
public enum CommandPaletteSearch {
    public static func results(
        query: String,
        matchingNotes: [NoteMetadata],
        commands: [AppCommandDescriptor] = AppCommandDescriptor.all
    ) -> [PaletteEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix(">") {
            let commandQuery = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return filterCommands(commands, query: commandQuery).map { .command($0) }
        }

        if trimmed.isEmpty {
            let noteEntries = matchingNotes.prefix(6).map { PaletteEntry.note($0) }
            let commandEntries = commands.map { PaletteEntry.command($0) }
            return noteEntries + commandEntries
        }

        let noteEntries = matchingNotes.map { PaletteEntry.note($0) }
        let commandEntries = filterCommands(commands, query: trimmed).map { PaletteEntry.command($0) }
        return noteEntries + commandEntries
    }

    private static func filterCommands(
        _ commands: [AppCommandDescriptor],
        query: String
    ) -> [AppCommandDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commands }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        return commands.filter { command in
            let searchable = ([command.title, command.subtitle] + command.keywords).joined(separator: " ")
            return tokens.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
        }
    }
}
