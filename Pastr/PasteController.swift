import AppKit

final class PasteController {
    private var previousApp: NSRunningApplication?
    private let pasteQueue = PasteQueue.shared

    func captureFrontmostApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    func paste(item: ClipboardItem, after delay: TimeInterval) {
        item.write(to: .general)

        guard let targetApp = previousApp else {
            triggerPasteShortcut(after: delay)
            return
        }

        targetApp.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.triggerPasteShortcut(after: 0)
        }
    }

    func pastePlainText(_ text: String, after delay: TimeInterval) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if let targetApp = previousApp {
            targetApp.activate(options: [.activateIgnoringOtherApps])
        }
        triggerPasteShortcut(after: delay)
    }

    /// Paste the next item from the queue. Returns true if an item was pasted.
    @discardableResult
    func pasteNextFromQueue(after delay: TimeInterval) -> Bool {
        guard let item = pasteQueue.dequeue() else {
            return false
        }
        paste(item: item, after: delay)
        return true
    }

    /// Check if queue mode is active and there are items to paste
    var canPasteFromQueue: Bool {
        pasteQueue.isActive && pasteQueue.hasItems
    }

    private func triggerPasteShortcut(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand

            cmdDown?.post(tap: .cgSessionEventTap)
            vDown?.post(tap: .cgSessionEventTap)
            vUp?.post(tap: .cgSessionEventTap)
            cmdUp?.post(tap: .cgSessionEventTap)
        }
    }
}
