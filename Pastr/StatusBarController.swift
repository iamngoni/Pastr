import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastr")
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }
    }

    @objc private func handleStatusItemClick() {
        onToggle()
    }
}
