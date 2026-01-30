import AppKit
import Carbon

final class HotKeyManager {
    static let shared = HotKeyManager()

    // Main panel toggle hotkey
    private var hotKeyRef: EventHotKeyRef?
    // Queue mode toggle hotkey
    private var queueHotKeyRef: EventHotKeyRef?

    private var eventHandlerRef: EventHandlerRef?
    private var onHotKey: () -> Void
    private var onQueueToggle: () -> Void

    init(onHotKey: @escaping () -> Void = {}, onQueueToggle: @escaping () -> Void = {}) {
        self.onHotKey = onHotKey
        self.onQueueToggle = onQueueToggle
    }

    func updateHandler(_ handler: @escaping () -> Void) {
        onHotKey = handler
    }

    func updateQueueHandler(_ handler: @escaping () -> Void) {
        onQueueToggle = handler
    }

    func registerDefaultHotKey() {
        register(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregisterMainHotKey()

        // Set up event handler if not already done
        setupEventHandler()

        var hotKeyID = EventHotKeyID(signature: fourCharCode("PSTR"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func registerQueueHotKey(keyCode: UInt32, modifiers: UInt32) {
        unregisterQueueHotKey()

        // Set up event handler if not already done
        setupEventHandler()

        var hotKeyID = EventHotKeyID(signature: fourCharCode("PSTQ"), id: 2)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &queueHotKeyRef)
    }

    private func setupEventHandler() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData, let event else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            // Get the hot key ID from the event
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            // Route to appropriate handler based on ID
            if hotKeyID.id == 1 {
                manager.onHotKey()
            } else if hotKeyID.id == 2 {
                manager.onQueueToggle()
            }

            return noErr
        }, 1, &eventSpec, selfPointer, &eventHandlerRef)
    }

    func unregisterHotKey() {
        unregisterMainHotKey()
        unregisterQueueHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func unregisterMainHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func unregisterQueueHotKey() {
        if let queueHotKeyRef {
            UnregisterEventHotKey(queueHotKeyRef)
            self.queueHotKeyRef = nil
        }
    }

    private func fourCharCode(_ value: String) -> OSType {
        let scalars = value.unicodeScalars
        var result: UInt32 = 0
        for scalar in scalars {
            result = (result << 8) + scalar.value
        }
        return OSType(result)
    }
}
