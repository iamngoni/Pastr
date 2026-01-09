import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let hotKeyManager = HotKeyManager.shared
    private var panelWindowController: PanelWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var pasteController: PasteController?
    private let historyStore = ClipboardHistoryStore.shared
    private let settingsStore = SettingsStore.shared
    private let pinnedStore = PinnedStore.shared
    private var onboardingController: OnboardingWindowController?
    private var settingsWindow: NSWindow?
    private let clipboardActions = ClipboardActions()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        hotKeyManager.register(keyCode: settingsStore.hotKeyKeyCode, modifiers: settingsStore.hotKeyModifiers)

        clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        clipboardMonitor?.start()

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
    }

    private func bindSettings() {
        settingsStore.$showInMenuBar
            .sink { [weak self] visible in
                self?.statusBarController?.setVisible(visible)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterHotKey()
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
