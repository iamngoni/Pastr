import AppKit
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
    private let clipboardActions = ClipboardActions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
            onUpdatePinnedTitle: { [weak self] item, title in
                self?.historyStore.updatePinnedTitle(for: item, title: title)
            }
        )

        statusBarController = StatusBarController { [weak self] in
            self?.togglePanel()
        }

        hotKeyManager.updateHandler { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.register(keyCode: settingsStore.hotKeyKeyCode, modifiers: settingsStore.hotKeyModifiers)

        clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        clipboardMonitor?.start()

        historyStore.mergePinned(pinnedStore.fetchPinned())

        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
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
        pasteController.paste(item: item, after: 0.08)
    }

    private func handlePastePlainText(item: ClipboardItem) {
        guard let pasteController else { return }
        panelWindowController?.hidePanel()
        pasteController.pastePlainText(item.plainText ?? item.previewText, after: 0.08)
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController { [weak self] in
            self?.settingsStore.hasCompletedOnboarding = true
        }
        onboardingController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
