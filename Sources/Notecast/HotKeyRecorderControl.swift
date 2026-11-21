import AppKit
import Carbon.HIToolbox
import NotecastCore

/// Interactive macOS shortcut recorder button that captures a valid global `HotKeyCombo`.
@MainActor
final class HotKeyRecorderControl: NSView {
    var combo: HotKeyCombo {
        didSet {
            if !isRecording {
                updateAppearance()
            }
        }
    }

    var onHotKeyRecorded: ((HotKeyCombo) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    var onInvalidShortcut: ((String) -> Void)?

    private(set) var isRecording = false
    private nonisolated(unsafe) var eventMonitor: Any?

    private let button = NSButton()

    init(combo: HotKeyCombo) {
        self.combo = combo
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
        setupView()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 28)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopRecording(notify: true)
        }
    }

    func cancelRecordingIfNeeded() {
        stopRecording(notify: true)
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        button.target = self
        button.action = #selector(handleButtonClick)
        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
    }

    @objc private func handleButtonClick() {
        if isRecording {
            stopRecording(notify: true)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        updateAppearance()
        onRecordingStateChanged?(true)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let shouldConsume = MainActor.assumeIsolated {
                guard let self, self.isRecording else { return false }
                return self.handleRecordedKeyDown(keyCode: keyCode, modifierFlags: modifierFlags)
            }
            return shouldConsume ? nil : event
        }
    }

    private func stopRecording(notify: Bool) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        guard isRecording else { return }
        isRecording = false
        updateAppearance()
        if notify {
            onRecordingStateChanged?(false)
        }
    }

    private func handleRecordedKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        if Int(keyCode) == kVK_Escape {
            stopRecording(notify: true)
            return true
        }

        guard let captured = HotKeyCombo.from(keyCode: keyCode, modifierFlags: modifierFlags) else {
            NSSound.beep()
            onInvalidShortcut?("Include ⌘, ⌥, or ⌃ (or use F1–F19).")
            return true
        }

        combo = captured
        stopRecording(notify: false)
        onHotKeyRecorded?(captured)
        onRecordingStateChanged?(false)
        return true
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isRecording {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
                layer?.borderColor = NSColor.controlAccentColor.cgColor
                button.title = "Press shortcut…"
                button.contentTintColor = .controlAccentColor
            } else {
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                layer?.borderColor = NSColor.separatorColor.cgColor
                button.title = combo.displayString
                button.contentTintColor = .labelColor
            }
        }
    }
}
