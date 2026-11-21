import Foundation

/// Lightweight metadata for a single Markdown note in `NoteLibraryStore`.
public struct NoteMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var preview: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, title: String, preview: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.preview = preview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Thread-safe, atomic multi-note library backed by `<uuid>.md` files and an `index.json` manifest.
public final class NoteLibraryStore: @unchecked Sendable {
    public static let defaultStarterContent = """
    # Notecast
    Press **⌥⌘N** anytime to show or hide this floating scratchpad.

    - [ ] Press **⌘P** for search & commands, **⌘⇧P** for notes search
    - [ ] Press **⌘N** for a new note, **⌘L** to browse notes
    - [x] Curated surfaces with active neon glow
    > Tip: Resize or drag the top bar — layout & notes auto-save.
    """

    private struct IndexFile: Codable {
        var notes: [NoteMetadata]
        var lastOpenedNoteID: UUID?
    }

    public let directoryURL: URL

    private let indexURL: URL
    private let legacyScratchpadURL: URL?
    private let useStarterIfEmpty: Bool
    private let ioQueue = DispatchQueue(label: "com.notecast.notelibrary", qos: .utility)

    private var index = IndexFile(notes: [], lastOpenedNoteID: nil)
    private var lastSavedByID: [UUID: String] = [:]
    private var pendingNoteID: UUID?
    private var pendingContent: String?
    private var pendingWorkItem: DispatchWorkItem?

    private static let leadingMarkdownPrefixRegex = try! NSRegularExpression(
        pattern: #"^(?:#{1,6}\s+|>\s*|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|\d+\.\s+)+"#
    )
    private static let inlineItalicStarsRegex = try! NSRegularExpression(
        pattern: #"(?<!\w)\*([^*\n]+)\*(?!\w)"#
    )

    public static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseDir
            .appendingPathComponent("Notecast", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
    }

    public init(
        directoryURL: URL = NoteLibraryStore.defaultDirectoryURL(),
        legacyScratchpadURL: URL? = NoteStore.defaultFileURL(),
        useStarterIfEmpty: Bool = true
    ) {
        self.directoryURL = directoryURL
        self.indexURL = directoryURL.appendingPathComponent("index.json", isDirectory: false)
        self.legacyScratchpadURL = legacyScratchpadURL
        self.useStarterIfEmpty = useStarterIfEmpty

        ioQueue.sync {
            loadOrInitializeIndexOnQueue()
        }
    }

    /// Extracts a clean title and 1-line preview from Markdown content.
    public static func extractTitleAndPreview(from content: String) -> (title: String, preview: String) {
        let nonEmptyLines = content
            .components(separatedBy: .newlines)
            .map { cleanMarkdownLine($0) }
            .filter { !$0.isEmpty }

        let rawTitle = nonEmptyLines.first ?? ""
        let title = rawTitle.isEmpty ? "Untitled Note" : truncate(rawTitle, maxLength: 80)

        let rawPreview = nonEmptyLines.count > 1 ? nonEmptyLines[1] : ""
        let preview = truncate(rawPreview, maxLength: 100)
        return (title, preview)
    }

    /// Returns all notes sorted by `updatedAt` descending.
    public func allNotes() -> [NoteMetadata] {
        ioQueue.sync {
            sortedNotes(index.notes)
        }
    }

    /// Returns the last opened note, or the most recent note (creating one if the library is empty).
    public func lastOpenedNote() -> NoteMetadata {
        ioQueue.sync {
            if let lastID = index.lastOpenedNoteID,
               let existing = index.notes.first(where: { $0.id == lastID })
            {
                return existing
            }
            if let mostRecent = sortedNotes(index.notes).first {
                index.lastOpenedNoteID = mostRecent.id
                try? writeIndexAtomicallyOnQueue()
                return mostRecent
            }

            let initial = useStarterIfEmpty ? Self.defaultStarterContent : ""
            if let created = try? createNoteOnQueue(initialContent: initial) {
                return created
            }
            return NoteMetadata(
                id: UUID(),
                title: "Untitled Note",
                preview: "",
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }

    /// Loads the UTF-8 content for `id`, preferring any unsaved pending buffer.
    public func loadContent(for id: UUID) -> String {
        ioQueue.sync {
            if pendingNoteID == id, let pendingContent {
                return pendingContent
            }
            let url = noteFileURL(for: id)
            guard let data = try? Data(contentsOf: url) else {
                return ""
            }
            let text = String(decoding: data, as: UTF8.self)
            lastSavedByID[id] = text
            return text
        }
    }

    /// Records `id` as the last opened note and persists `index.json` atomically.
    public func setLastOpenedNote(_ id: UUID) {
        ioQueue.sync {
            guard index.notes.contains(where: { $0.id == id }), index.lastOpenedNoteID != id else {
                return
            }
            index.lastOpenedNoteID = id
            try? writeIndexAtomicallyOnQueue()
        }
    }

    /// Flushes any pending edit, creates a new note on disk, marks it active, and returns its metadata.
    @discardableResult
    public func createNote(initialContent: String = "") throws -> NoteMetadata {
        try ioQueue.sync {
            try flushPendingOnQueue()
            return try createNoteOnQueue(initialContent: initialContent)
        }
    }

    /// Deletes a note by ID and returns the next active note (creating an empty fallback note if none remain).
    @discardableResult
    public func deleteNote(id: UUID) throws -> NoteMetadata {
        try ioQueue.sync {
            if pendingNoteID == id {
                pendingWorkItem?.cancel()
                pendingWorkItem = nil
                pendingNoteID = nil
                pendingContent = nil
            } else {
                try flushPendingOnQueue()
            }

            let fileURL = noteFileURL(for: id)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            lastSavedByID.removeValue(forKey: id)
            index.notes.removeAll { $0.id == id }

            let nextNote: NoteMetadata
            if let candidate = sortedNotes(index.notes).first {
                nextNote = candidate
                index.lastOpenedNoteID = candidate.id
                try writeIndexAtomicallyOnQueue()
            } else {
                nextNote = try createNoteOnQueue(initialContent: "")
            }

            return nextNote
        }
    }

    /// Schedules a debounced atomic write of `<noteID>.md` and `index.json`.
    public func scheduleSave(
        noteID: UUID,
        content: String,
        delay: TimeInterval = 0.4,
        onSaved: (@Sendable (NoteMetadata) -> Void)? = nil
    ) {
        ioQueue.async { [weak self] in
            guard let self else { return }

            if let existingID = self.pendingNoteID, existingID != noteID {
                try? self.flushPendingOnQueue()
            }

            self.pendingWorkItem?.cancel()
            self.pendingNoteID = noteID
            self.pendingContent = content

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let targetID = self.pendingNoteID, let textToWrite = self.pendingContent else {
                    return
                }
                self.pendingWorkItem = nil
                self.pendingNoteID = nil
                self.pendingContent = nil

                do {
                    let updated = try self.persistNoteOnQueue(id: targetID, content: textToWrite)
                    onSaved?(updated)
                } catch {
                    self.pendingNoteID = targetID
                    self.pendingContent = textToWrite
                }
            }

            self.pendingWorkItem = workItem
            self.ioQueue.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
        }
    }

    /// Cancels any debounced write and synchronously flushes pending or provided note content atomically.
    public func flushSync(noteID: UUID? = nil, content: String? = nil) throws {
        try ioQueue.sync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil

            if let noteID, let content {
                if let existingID = pendingNoteID, existingID != noteID {
                    try flushPendingOnQueue()
                }
                pendingNoteID = noteID
                pendingContent = content
            }

            try flushPendingOnQueue()
        }
    }

    /// Searches notes case-insensitively across title, preview, and Markdown body, ranking title matches first.
    public func searchNotes(query: String) -> [NoteMetadata] {
        ioQueue.sync {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return sortedNotes(index.notes)
            }

            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            var scored: [(rank: Int, note: NoteMetadata)] = []

            for note in index.notes {
                let titleMatchesAll = tokens.allSatisfy { note.title.localizedCaseInsensitiveContains($0) }
                if titleMatchesAll {
                    scored.append((rank: 2, note: note))
                    continue
                }

                let previewMatchesAll = tokens.allSatisfy { note.preview.localizedCaseInsensitiveContains($0) }
                if previewMatchesAll {
                    scored.append((rank: 1, note: note))
                    continue
                }

                let body: String
                if pendingNoteID == note.id, let pendingContent {
                    body = pendingContent
                } else if let cached = lastSavedByID[note.id] {
                    body = cached
                } else if let data = try? Data(contentsOf: noteFileURL(for: note.id)) {
                    let loaded = String(decoding: data, as: UTF8.self)
                    lastSavedByID[note.id] = loaded
                    body = loaded
                } else {
                    body = ""
                }

                let bodyMatchesAll = tokens.allSatisfy { body.localizedCaseInsensitiveContains($0) }
                if bodyMatchesAll {
                    scored.append((rank: 0, note: note))
                }
            }

            return scored
                .sorted { lhs, rhs in
                    if lhs.rank != rhs.rank {
                        return lhs.rank > rhs.rank
                    }
                    if lhs.note.updatedAt != rhs.note.updatedAt {
                        return lhs.note.updatedAt > rhs.note.updatedAt
                    }
                    return lhs.note.id.uuidString < rhs.note.id.uuidString
                }
                .map(\.note)
        }
    }

    // MARK: - Queue-Internal Implementation

    private func loadOrInitializeIndexOnQueue() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: indexURL.path),
           let data = try? Data(contentsOf: indexURL),
           let decoded = try? makeDecoder().decode(IndexFile.self, from: data)
        {
            index = decoded
        } else {
            // First run for multi-note store: migrate legacy scratchpad.md if present.
            if let legacyURL = legacyScratchpadURL,
               fm.fileExists(atPath: legacyURL.path),
               let legacyData = try? Data(contentsOf: legacyURL)
            {
                let legacyText = String(decoding: legacyData, as: UTF8.self)
                _ = try? createNoteOnQueue(initialContent: legacyText)
            } else if useStarterIfEmpty {
                _ = try? createNoteOnQueue(initialContent: Self.defaultStarterContent)
            }
        }

        reconcileIndexWithDiskOnQueue()
    }

    private func reconcileIndexWithDiskOnQueue() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var mdByID: [UUID: URL] = [:]
        for file in files where file.pathExtension == "md" {
            let stem = file.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: stem) {
                mdByID[id] = file
            }
        }

        var changed = false

        let beforeCount = index.notes.count
        index.notes.removeAll { mdByID[$0.id] == nil }
        if index.notes.count != beforeCount {
            changed = true
        }

        let knownIDs = Set(index.notes.map(\.id))
        for (id, fileURL) in mdByID where !knownIDs.contains(id) {
            let data = (try? Data(contentsOf: fileURL)) ?? Data()
            let content = String(decoding: data, as: UTF8.self)
            lastSavedByID[id] = content
            let extracted = Self.extractTitleAndPreview(from: content)
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let created = values?.creationDate ?? Date()
            let updated = values?.contentModificationDate ?? created
            index.notes.append(
                NoteMetadata(
                    id: id,
                    title: extracted.title,
                    preview: extracted.preview,
                    createdAt: created,
                    updatedAt: updated
                )
            )
            changed = true
        }

        if let lastID = index.lastOpenedNoteID, !index.notes.contains(where: { $0.id == lastID }) {
            index.lastOpenedNoteID = sortedNotes(index.notes).first?.id
            changed = true
        } else if index.lastOpenedNoteID == nil, let first = sortedNotes(index.notes).first {
            index.lastOpenedNoteID = first.id
            changed = true
        }

        if changed {
            try? writeIndexAtomicallyOnQueue()
        }
    }

    private func createNoteOnQueue(initialContent: String) throws -> NoteMetadata {
        let now = Date()
        let id = UUID()
        let extracted = Self.extractTitleAndPreview(from: initialContent)
        let meta = NoteMetadata(
            id: id,
            title: extracted.title,
            preview: extracted.preview,
            createdAt: now,
            updatedAt: now
        )

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(initialContent.utf8).write(to: noteFileURL(for: id), options: [.atomic])
        lastSavedByID[id] = initialContent

        index.notes.insert(meta, at: 0)
        index.lastOpenedNoteID = id
        try writeIndexAtomicallyOnQueue()
        return meta
    }

    private func flushPendingOnQueue() throws {
        guard let noteID = pendingNoteID, let content = pendingContent else {
            pendingNoteID = nil
            pendingContent = nil
            return
        }
        _ = try persistNoteOnQueue(id: noteID, content: content)
        pendingNoteID = nil
        pendingContent = nil
    }

    private func persistNoteOnQueue(id: UUID, content: String) throws -> NoteMetadata {
        let extracted = Self.extractTitleAndPreview(from: content)
        let now = Date()

        let alreadySaved = lastSavedByID[id] == content
        if !alreadySaved {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: noteFileURL(for: id), options: [.atomic])
            lastSavedByID[id] = content
        }

        if let idx = index.notes.firstIndex(where: { $0.id == id }) {
            var meta = index.notes[idx]
            let metaChanged = meta.title != extracted.title || meta.preview != extracted.preview || !alreadySaved
            if metaChanged {
                meta.title = extracted.title
                meta.preview = extracted.preview
                if !alreadySaved {
                    meta.updatedAt = now
                }
                index.notes[idx] = meta
                try writeIndexAtomicallyOnQueue()
            }
            return meta
        } else {
            let meta = NoteMetadata(
                id: id,
                title: extracted.title,
                preview: extracted.preview,
                createdAt: now,
                updatedAt: now
            )
            index.notes.insert(meta, at: 0)
            index.lastOpenedNoteID = id
            try writeIndexAtomicallyOnQueue()
            return meta
        }
    }

    private func writeIndexAtomicallyOnQueue() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try makeEncoder().encode(index)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func noteFileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).md", isDirectory: false)
    }

    private func sortedNotes(_ notes: [NoteMetadata]) -> [NoteMetadata] {
        notes.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Title & Preview Cleaning

    private static func cleanMarkdownLine(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        let nsRange = NSRange(location: 0, length: (result as NSString).length)
        result = leadingMarkdownPrefixRegex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "")
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "~~", with: "")
        result = result.replacingOccurrences(of: "`", with: "")

        let starRange = NSRange(location: 0, length: (result as NSString).length)
        result = inlineItalicStarsRegex.stringByReplacingMatches(in: result, range: starRange, withTemplate: "$1")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let idx = text.index(text.startIndex, offsetBy: max(0, maxLength - 1))
        return String(text[..<idx]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
