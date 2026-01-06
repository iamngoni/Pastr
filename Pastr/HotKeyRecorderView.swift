import Carbon
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let onChange: () -> Void

    func makeNSView(context: Context) -> HotKeyRecorderField {
        let field = HotKeyRecorderField()
        field.onKeyCapture = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            modifiers = newModifiers
            onChange()
        }
        field.updateDisplay(keyCode: keyCode, modifiers: modifiers)
        return field
    }

    func updateNSView(_ nsView: HotKeyRecorderField, context: Context) {
        nsView.updateDisplay(keyCode: keyCode, modifiers: modifiers)
    }
}

final class HotKeyRecorderField: NSView {
    var onKeyCapture: ((UInt32, UInt32) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor

        label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false

        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        label.stringValue = "Type shortcut…"
        label.textColor = NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 1)
        layer?.backgroundColor = NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 0.15).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 0.5).cgColor

        // Use local event monitor to capture key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            if event.type == .keyDown {
                // Escape cancels recording
                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                let keyCode = UInt32(event.keyCode)
                let modifiers = HotKeyRecorderField.modifierFlags(from: event.modifierFlags)

                // Require at least one modifier key
                if modifiers != 0 {
                    self.currentKeyCode = keyCode
                    self.currentModifiers = modifiers
                    self.onKeyCapture?(keyCode, modifiers)
                    self.stopRecording()
                }
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        label.textColor = .white
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer?.borderWidth = 0

        updateDisplay(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    func updateDisplay(keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        if !isRecording {
            label.stringValue = HotKeyRecorderField.displayString(for: keyCode, modifiers: modifiers)
        }
    }

    private static func modifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }

    private static func displayString(for keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        parts.append(keyLabel(for: keyCode))
        return parts.joined()
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case 36: return "⏎"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            if let scalar = keyCodeToUnicode[keyCode] {
                return String(scalar).uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private static let keyCodeToUnicode: [UInt32: Character] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/"
    ]
}
