import AppKit

final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onToggle: () -> Void
    private let onOpenSettings: () -> Void

    init(onToggle: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onOpenSettings = onOpenSettings
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
            // Use custom menu bar icon from assets, fallback to system symbol
            if let customIcon = NSImage(named: "MenuBarIcon") {
                customIcon.isTemplate = true
                button.image = customIcon
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastr")
            }
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggle()
            return
        }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Pastr", action: #selector(showPastr), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Pastr", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showPastr() {
        onToggle()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
