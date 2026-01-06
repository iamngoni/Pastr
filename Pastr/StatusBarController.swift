import AppKit

final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        createStatusItem()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                createStatusItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastr")
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }
    }

    @objc private func handleStatusItemClick() {
        onToggle()
    }
}
