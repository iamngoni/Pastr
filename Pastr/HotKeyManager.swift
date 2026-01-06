import AppKit
import Carbon

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onHotKey: () -> Void

    init(onHotKey: @escaping () -> Void) {
        self.onHotKey = onHotKey
    }

    func registerDefaultHotKey() {
        register(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotKey()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotKey()
            return noErr
        }, 1, &eventSpec, selfPointer, &eventHandlerRef)

        var hotKeyID = EventHotKeyID(signature: fourCharCode("PSTR"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
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
