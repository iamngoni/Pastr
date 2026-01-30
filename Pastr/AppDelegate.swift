import AppKit
import Combine
import Sentry
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let hotKeyManager = HotKeyManager.shared
    private let hotCornerMonitor = HotCornerMonitor.shared
    private var panelWindowController: PanelWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var pasteController: PasteController?
    private let historyStore = ClipboardHistoryStore.shared
    private let settingsStore = SettingsStore.shared
    private let pinnedStore = PinnedStore.shared
    private let pasteQueue = PasteQueue.shared
    private var onboardingController: OnboardingWindowController?
    private var settingsWindow: NSWindow?
    private let clipboardActions = ClipboardActions()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SentrySDK.start { options in
            options.dsn = "https://47a5a589a8006e54c4ea2b8de115b482@o1107818.ingest.us.sentry.io/4510679814307840"
#if DEBUG
            options.debug = true
#endif
        }

        NSApp.setActivationPolicy(.accessory)

        // Request accessibility permissions (needed for pasting via CGEvent)
        requestAccessibilityPermissions()

        pasteController = PasteController()
        panelWindowController = PanelWindowController(
            historyStore: historyStore,
            onSelect: { [weak self] item in
                self?.handlePaste(item: item)
            },
            onTogglePin: { [weak self] item in
                self?.historyStore.togglePin(for: item)
            },
            onCopy: { [weak self] item in
                self?.clipboardActions.copyToClipboard(item)
            },
            onPastePlainText: { [weak self] item in
                self?.handlePastePlainText(item: item)
            },
            onOpenLink: { [weak self] item in
                self?.clipboardActions.openLink(item)
            },
            onRevealInFinder: { [weak self] item in
                self?.clipboardActions.revealInFinder(item)
            },
            onDelete: { [weak self] items in
                self?.historyStore.delete(items)
            },
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onAddToCollection: { [weak self] item, collectionId in
                self?.historyStore.addToCollection(item, collectionId: collectionId)
            },
            onRemoveFromCollection: { [weak self] item, collectionId in
                self?.historyStore.removeFromCollection(item, collectionId: collectionId)
            }
        )

        statusBarController = StatusBarController(
            onToggle: { [weak self] in
                self?.togglePanel()
            },
            onOpenSettings: { [weak self] in
                self?.showSettings()
            }
        )

        hotKeyManager.updateHandler { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.updateQueueHandler { [weak self] in
            self?.toggleQueueMode()
        }
        hotKeyManager.register(keyCode: settingsStore.hotKeyKeyCode, modifiers: settingsStore.hotKeyModifiers)
        hotKeyManager.registerQueueHotKey(keyCode: settingsStore.queueModeKeyCode, modifiers: settingsStore.queueModeModifiers)

        clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        clipboardMonitor?.start()

        // Setup hot corner
        hotCornerMonitor.setHandler { [weak self] in
            self?.togglePanel()
        }
        hotCornerMonitor.start()

        if settingsStore.iCloudSyncEnabled {
            if let cloudItems = try? pinnedStore.fetchAll() {
                historyStore.mergeCloudItems(cloudItems)
            }
            historyStore.syncAllToCloud()
        }

        bindSettings()

        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }

        // Check for updates on launch if enabled
        if settingsStore.checkForUpdatesAutomatically {
            Task {
                await UpdateChecker.shared.checkForUpdates(silent: true)
            }
        }
    }

    private func bindSettings() {
        settingsStore.$showInMenuBar
            .sink { [weak self] visible in
                self?.statusBarController?.setVisible(visible)
            }
            .store(in: &cancellables)

        // Restart hot corner monitor when settings change
        settingsStore.$hotCorner
            .sink { [weak self] _ in
                self?.hotCornerMonitor.restart()
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterHotKey()
        hotCornerMonitor.stop()
        clipboardMonitor?.stop()
    }

    private func togglePanel() {
        if panelWindowController?.isPanelVisible == true {
            panelWindowController?.hidePanel()
        } else {
            pasteController?.captureFrontmostApp()
            panelWindowController?.showPanel()
        }
    }

    private func toggleQueueMode() {
        pasteQueue.toggle()
        // Play sound to indicate mode change
        if pasteQueue.isActive {
            SoundManager.playPinSound()
        }
        // Update status bar to reflect queue mode
        statusBarController?.updateQueueStatus(active: pasteQueue.isActive, count: pasteQueue.remainingCount)
    }

    private func handlePaste(item: ClipboardItem) {
        guard let pasteController else { return }
        panelWindowController?.hidePanel()
        pasteController.paste(item: item, after: settingsStore.pasteDelay)
    }

    private func handlePastePlainText(item: ClipboardItem) {
        guard let pasteController else { return }
        panelWindowController?.hidePanel()
        pasteController.pastePlainText(item.plainText ?? item.previewText, after: settingsStore.pasteDelay)
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController { [weak self] in
            self?.settingsStore.hasCompletedOnboarding = true
        }
        onboardingController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func requestAccessibilityPermissions() {
        // Check without prompting - onboarding handles the initial prompt
        let trusted = AXIsProcessTrustedWithOptions(nil)
        if !trusted {
            print("Accessibility permissions not granted. Paste functionality requires accessibility access.")
        }
    }

    private func showSettings() {
        panelWindowController?.hidePanel()

        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            settings: settingsStore,
            historyStore: historyStore,
            hotKeyManager: hotKeyManager
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pastr Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
