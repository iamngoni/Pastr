import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotKeyManager: HotKeyManager?
    private var panelWindowController: PanelWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var pasteController: PasteController?
    private let historyStore = ClipboardHistoryStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        pasteController = PasteController()
        panelWindowController = PanelWindowController(historyStore: historyStore) { [weak self] item in
            self?.handlePaste(item: item)
        }

        statusBarController = StatusBarController { [weak self] in
            self?.togglePanel()
        }

        hotKeyManager = HotKeyManager { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager?.registerDefaultHotKey()

        clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        clipboardMonitor?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregisterHotKey()
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
}
