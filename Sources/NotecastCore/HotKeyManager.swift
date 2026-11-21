import Carbon.HIToolbox
import Foundation

private let notecastHotKeySignature: OSType = 0x4E43_5354 // 'NCST'
private let notecastHotKeyID: UInt32 = 1

/// Manages global hotkey registration via Carbon `RegisterEventHotKey` (no Accessibility permissions required).
@MainActor
public final class HotKeyManager {
    public var onHotKeyPressed: (() -> Void)?
    public private(set) var activeCombo: HotKeyCombo?

    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?
    private var isSuspended = false

    public init() {
        installHandlerIfNeeded()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Registers a global hotkey, replacing any existing registration.
    @discardableResult
    public func register(_ combo: HotKeyCombo) -> OSStatus {
        installHandlerIfNeeded()
        unregisterHotKeyOnly()
        isSuspended = false

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: notecastHotKeySignature, id: notecastHotKeyID)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            hotKeyRef = ref
            activeCombo = combo
        } else {
            hotKeyRef = nil
        }

        return status
    }

    /// Unregisters the active hotkey and clears `activeCombo`.
    public func unregister() {
        unregisterHotKeyOnly()
        activeCombo = nil
        isSuspended = false
    }

    /// Temporarily unregisters the hotkey while recording a new shortcut.
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterHotKeyOnly()
    }

    /// Restores the previously active hotkey if still suspended.
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        if hotKeyRef == nil, let combo = activeCombo {
            _ = register(combo)
        }
    }

    /// Unregisters hotkey and removes the Carbon event handler on app termination.
    public func teardown() {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func unregisterHotKeyOnly() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status == noErr {
            eventHandlerRef = handler
        }
    }

    fileprivate func handleHotKeyEvent(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == notecastHotKeySignature,
              hotKeyID.id == notecastHotKeyID,
              !isSuspended
        else {
            return OSStatus(eventNotHandledErr)
        }
        onHotKeyPressed?()
        return noErr
    }
}

private let hotKeyEventCallback: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        manager.handleHotKeyEvent(hotKeyID)
    }
}
