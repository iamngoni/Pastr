import AppKit

final class ClipboardWriter {
    private var previousApp: NSRunningApplication?
    private let pasteQueue = PasteQueue.shared

    func captureFrontmostApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    func copy(item: ClipboardItem, returnFocusAfter delay: TimeInterval) {
        item.write(to: .general)
        returnFocus(after: delay)
    }

    func copyPlainText(_ text: String, returnFocusAfter delay: TimeInterval) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        returnFocus(after: delay)
    }

    /// Copy the next item from the queue. Returns true if an item was copied.
    @discardableResult
    func copyNextFromQueue(returnFocusAfter delay: TimeInterval) -> Bool {
        guard let item = pasteQueue.dequeue() else {
            return false
        }
        copy(item: item, returnFocusAfter: delay)
        return true
    }

    /// Check if queue mode is active and there are items to copy.
    var canCopyFromQueue: Bool {
        pasteQueue.isActive && pasteQueue.hasItems
    }

    private func returnFocus(after delay: TimeInterval) {
        guard let targetApp = previousApp else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            targetApp.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
