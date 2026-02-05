import AppKit

final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onToggle: () -> Void
    private let onOpenSettings: () -> Void
    private var queueActive: Bool = false
    private var queueCount: Int = 0

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

    func updateQueueStatus(active: Bool, count: Int) {
        queueActive = active
        queueCount = count
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        if queueActive {
            // Show queue indicator - use a different icon or add badge
            if let queueIcon = NSImage(systemSymbolName: "list.number", accessibilityDescription: "Queue Mode Active") {
                queueIcon.isTemplate = true
                button.image = queueIcon
            }
            // Add count badge
            button.title = queueCount > 0 ? " \(queueCount)" : ""
        } else {
            // Reset to normal icon
            if let customIcon = NSImage(named: "MenuBarIcon") {
                customIcon.isTemplate = true
                button.image = customIcon
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastr")
            }
            button.title = ""
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

        // Queue mode items
        let pasteQueue = PasteQueue.shared
        if pasteQueue.isActive {
            let queueStatusItem = NSMenuItem(title: "Queue: \(pasteQueue.remainingCount) items", action: nil, keyEquivalent: "")
            queueStatusItem.isEnabled = false
            menu.addItem(queueStatusItem)

            let stopQueueItem = NSMenuItem(title: "Stop Queue Mode", action: #selector(stopQueueMode), keyEquivalent: "")
            stopQueueItem.target = self
            menu.addItem(stopQueueItem)
        } else {
            let startQueueItem = NSMenuItem(title: "Start Queue Mode", action: #selector(startQueueMode), keyEquivalent: "")
            startQueueItem.target = self
            menu.addItem(startQueueItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
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

    @objc private func startQueueMode() {
        PasteQueue.shared.start()
        updateQueueStatus(active: true, count: 0)
        SoundManager.playPinSound()
    }

    @objc private func stopQueueMode() {
        PasteQueue.shared.stop()
        updateQueueStatus(active: false, count: 0)
    }
}
