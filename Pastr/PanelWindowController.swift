import AppKit
import QuartzCore
import ScreenCaptureKit
import SwiftUI

final class PanelWindowController {
    private let panel: PastrPanel
    private let historyStore: ClipboardHistoryStore
    private let settingsStore = SettingsStore.shared
    private let viewModel: PanelViewModel
    private let onSelect: (ClipboardItem) -> Void
    private let onTogglePin: (ClipboardItem) -> Void
    private let onCopy: (ClipboardItem) -> Void
    private let onPastePlainText: (ClipboardItem) -> Void
    private let onOpenLink: (ClipboardItem) -> Void
    private let onRevealInFinder: (ClipboardItem) -> Void
    private let onUpdatePinnedTitle: (ClipboardItem, String) -> Void
    private let onDelete: ([ClipboardItem]) -> Void
    private let onOpenSettings: () -> Void
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    var isPanelVisible: Bool {
        panel.isVisible
    }

    init(
        historyStore: ClipboardHistoryStore,
        onSelect: @escaping (ClipboardItem) -> Void,
        onTogglePin: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onPastePlainText: @escaping (ClipboardItem) -> Void,
        onOpenLink: @escaping (ClipboardItem) -> Void,
        onRevealInFinder: @escaping (ClipboardItem) -> Void,
        onUpdatePinnedTitle: @escaping (ClipboardItem, String) -> Void,
        onDelete: @escaping ([ClipboardItem]) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.historyStore = historyStore
        self.onSelect = onSelect
        self.onTogglePin = onTogglePin
        self.onCopy = onCopy
        self.onPastePlainText = onPastePlainText
        self.onOpenLink = onOpenLink
        self.onRevealInFinder = onRevealInFinder
        self.onUpdatePinnedTitle = onUpdatePinnedTitle
        self.onDelete = onDelete
        self.onOpenSettings = onOpenSettings
        self.viewModel = PanelViewModel(historyStore: historyStore)

        let panel = PastrPanel(
            contentRect: .init(x: 0, y: 0, width: 900, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let rootView = PanelView(
            viewModel: viewModel,
            onSelect: onSelect,
            onTogglePin: onTogglePin,
            onCopy: onCopy,
            onPastePlainText: onPastePlainText,
            onOpenLink: onOpenLink,
            onRevealInFinder: onRevealInFinder,
            onUpdatePinnedTitle: onUpdatePinnedTitle,
            onDelete: onDelete,
            onOpenSettings: onOpenSettings
        )
        panel.contentView = NSHostingView(rootView: rootView)

        self.panel = panel
    }

    func showPanel() {
        // Check if we should hide during screen sharing
        if !settingsStore.showDuringScreenSharing && isScreenBeingShared() {
            return
        }

        guard let screen = screenForCursor() else { return }
        let targetFrame = panelFrame(for: screen)
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -targetFrame.height - 12)

        viewModel.resetSelection()
        NSApp.activate(ignoringOtherApps: true)
        panel.setFrame(startFrame, display: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }

        startClickMonitor()
        startKeyMonitor()
    }

    private func isScreenBeingShared() -> Bool {
        // Check for common screen sharing apps
        let screenSharingApps = [
            "zoom.us",
            "com.microsoft.teams",
            "us.zoom.xos",
            "com.apple.FaceTime",
            "com.webex.meetingmanager",
            "com.google.Chrome", // For Google Meet
            "com.apple.ScreenSharing"
        ]

        // Check if any screen sharing apps are running and active
        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier,
               screenSharingApps.contains(where: { bundleId.contains($0) }) {
                // Additional heuristic: Check if the app is presenting
                if app.isActive || app.ownsMenuBar {
                    // This is a simplified check - true screen sharing detection
                    // would require more sophisticated APIs
                    return false // For now, don't block - let user control via setting
                }
            }
        }

        // Check for screen recording indicator (macOS shows an orange dot)
        // This is a best-effort detection using CGWindowListCopyWindowInfo
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if let ownerName = window[kCGWindowOwnerName as String] as? String,
                   ownerName.contains("screencapture") || ownerName.contains("ScreenSharing") {
                    return true
                }
            }
        }

        return false
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        stopClickMonitor()
        stopKeyMonitor()

        let endFrame = panel.frame.offsetBy(dx: 0, dy: -panel.frame.height - 12)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let margin: CGFloat = 18
        let height: CGFloat = 280
        let width = screen.visibleFrame.width - margin * 2
        let x = screen.visibleFrame.minX + margin
        let y = screen.visibleFrame.minY + margin
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenForCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }

    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Handle Cmd+A for select all
            if event.modifierFlags.contains(.command) && event.keyCode == 0 {
                self.viewModel.selectAll()
                return nil
            }

            switch event.keyCode {
            case 123: // Left arrow
                self.viewModel.selectPrevious()
                return nil
            case 124: // Right arrow
                self.viewModel.selectNext()
                return nil
            case 36, 76: // Enter/Return
                if let item = self.viewModel.selectedItem {
                    self.onSelect(item)
                }
                return nil
            case 51, 117: // Delete (backspace) or Forward Delete
                let itemsToDelete = self.viewModel.selectedItems
                if !itemsToDelete.isEmpty {
                    self.onDelete(itemsToDelete)
                    self.viewModel.clearMultiSelection()
                }
                return nil
            case 53: // Escape
                self.hidePanel()
                return nil
            default:
                return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

final class PastrPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
