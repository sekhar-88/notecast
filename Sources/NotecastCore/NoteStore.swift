import Foundation

/// Thread-safe, atomic Markdown scratchpad persistence backed by a serial I/O queue.
public final class NoteStore: @unchecked Sendable {
    public static let defaultStarterContent = """
    # Notecast
    Press **⌥ Space** anytime to show or hide this floating scratchpad.

    - [ ] Jot down quick thoughts, links, or **tasks**
    - [x] Stays floating while you work underneath
    > Tip: Resize or drag anywhere on the top bar — layout & notes auto-save.
    """

    public let fileURL: URL

    private let useStarterIfMissing: Bool
    private let ioQueue = DispatchQueue(label: "com.notecast.notestore", qos: .utility)
    private var lastSavedText: String?
    private var pendingText: String?
    private var pendingWorkItem: DispatchWorkItem?

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseDir
            .appendingPathComponent("Notecast", isDirectory: true)
            .appendingPathComponent("scratchpad.md", isDirectory: false)
    }

    public init(fileURL: URL = NoteStore.defaultFileURL(), useStarterIfMissing: Bool = true) {
        self.fileURL = fileURL
        self.useStarterIfMissing = useStarterIfMissing
    }

    /// Loads the current scratchpad text from disk, or returns starter content if missing.
    public func load() -> String {
        ioQueue.sync {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: fileURL.path) else {
                lastSavedText = nil
                pendingText = nil
                return useStarterIfMissing ? Self.defaultStarterContent : ""
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let content = String(decoding: data, as: UTF8.self)
                lastSavedText = content
                pendingText = nil
                return content
            } catch {
                return useStarterIfMissing ? Self.defaultStarterContent : ""
            }
        }
    }

    /// Schedules a debounced atomic write on the background I/O queue.
    public func scheduleSave(
        _ text: String,
        delay: TimeInterval = 0.4,
        onSaved: (@Sendable () -> Void)? = nil
    ) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.pendingWorkItem?.cancel()
            self.pendingText = text

            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let textToWrite = self.pendingText
                self.pendingWorkItem = nil
                self.pendingText = nil

                guard let textToWrite else { return }
                if textToWrite != self.lastSavedText {
                    do {
                        try self.writeAtomically(textToWrite)
                        self.lastSavedText = textToWrite
                        onSaved?()
                    } catch {
                        // Preserve pendingText so a subsequent flushSync can retry.
                        self.pendingText = textToWrite
                    }
                } else {
                    onSaved?()
                }
            }

            self.pendingWorkItem = item
            self.ioQueue.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        }
    }

    /// Cancels any debounced write and synchronously writes pending (or provided) text atomically.
    public func flushSync(_ text: String? = nil) throws {
        try ioQueue.sync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil

            if let text {
                pendingText = text
            }

            guard let textToWrite = pendingText else {
                return
            }

            if textToWrite != lastSavedText {
                try writeAtomically(textToWrite)
                lastSavedText = textToWrite
            }
            pendingText = nil
        }
    }

    private func writeAtomically(_ text: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL, options: [.atomic])
    }
}
