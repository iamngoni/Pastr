import AppKit
import Combine
import Sentry
import SwiftUI

enum SentryBootstrap {
    private static let startOnce: Void = {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
        guard !isRunningTests else { return }

        SentrySDK.start { options in
            options.dsn = "https://47a5a589a8006e54c4ea2b8de115b482@o1107818.ingest.us.sentry.io/4510679814307840"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            options.releaseName = "\(version)+\(build)"
            options.dist = build
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2
            options.enableWatchdogTerminationTracking = true
            // Link previews intentionally tolerate failures from third-party websites. Reporting
            // those responses as Pastr errors creates noisy issues for servers we do not control.
            options.enableCaptureFailedRequests = false
            options.sendDefaultPii = false
#if DEBUG
            options.environment = "development"
            options.debug = true
#else
            options.environment = "production"
#endif
        }
        SentrySDK.configureScope { scope in
            scope.setTag(value: "macOS", key: "app.platform")
        }
    }()

    static func start() {
        _ = startOnce
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private lazy var hotKeyManager = HotKeyManager.shared
    private lazy var hotCornerMonitor = HotCornerMonitor.shared
    private var panelWindowController: PanelWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private var clipboardWriter: ClipboardWriter?
    private lazy var historyStore = ClipboardHistoryStore.shared
    private lazy var settingsStore = SettingsStore.shared
    private lazy var pinnedStore = PinnedStore.shared
    private lazy var pasteQueue = PasteQueue.shared
    private var onboardingController: OnboardingWindowController?
    private var whatsNewController: WhatsNewWindowController?
    private var settingsWindow: NSWindow?
    private let clipboardActions = ClipboardActions()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSApplication is fully initialized here. Starting Sentry earlier can make its session
        // tracker initialize NSApplication recursively during SwiftUI app bootstrap.
        SentryBootstrap.start()

        NSApp.setActivationPolicy(.accessory)

        clipboardWriter = ClipboardWriter()
        panelWindowController = PanelWindowController(
            historyStore: historyStore,
            onSelect: { [weak self] item in
                self?.copyToClipboard(item: item)
            },
            onTogglePin: { [weak self] item in
                self?.historyStore.togglePin(for: item)
            },
            onCopy: { [weak self] item in
                self?.clipboardActions.copyToClipboard(item)
            },
            onCopyPlainText: { [weak self] item in
                self?.copyPlainText(item: item)
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

        // Build the panel's SwiftUI content after launch settles rather than inline
        // (launch hangs, Sentry PASTR-3T / PASTR-3S).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.panelWindowController?.prewarm()
        }

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
            historyStore.syncNow()
        }

        bindSettings()

        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        } else {
            showWhatsNewIfNeeded()
        }
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Show the "What's New" sheet once after the app updates to a new version.
    private func showWhatsNewIfNeeded() {
        let current = currentAppVersion
        guard !current.isEmpty, settingsStore.lastSeenVersion != current else { return }

        let controller = WhatsNewWindowController(version: current) { [weak self] in
            self?.settingsStore.lastSeenVersion = current
        }
        whatsNewController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        // Debounced writers: force any pending snapshots to disk before exit.
        ClipboardHistoryStore.shared.flushPendingWrites()
        AIEnrichmentStore.shared.flush()
        TagStore.shared.flush()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AIEnrichmentStore.shared.refreshAppleIntelligenceAvailability()
    }

    private func togglePanel() {
        if panelWindowController?.isPanelVisible == true {
            panelWindowController?.hidePanel()
        } else {
            clipboardWriter?.captureFrontmostApp()
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

    private func copyToClipboard(item: ClipboardItem) {
        guard let clipboardWriter else { return }
        panelWindowController?.hidePanel()
        clipboardWriter.copy(item: item, returnFocusAfter: settingsStore.pasteDelay)
    }

    private func copyPlainText(item: ClipboardItem) {
        guard let clipboardWriter else { return }
        panelWindowController?.hidePanel()
        clipboardWriter.copyPlainText(item.plainText ?? item.previewText, returnFocusAfter: settingsStore.pasteDelay)
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController { [weak self] in
            guard let self else { return }
            self.settingsStore.hasCompletedOnboarding = true
            // New users start onboarded onto the current version, so they skip "What's New".
            self.settingsStore.lastSeenVersion = self.currentAppVersion
        }
        onboardingController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
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
