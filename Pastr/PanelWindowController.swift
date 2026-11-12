import Combine
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
    private let onCopyPlainText: (ClipboardItem) -> Void
    private let onOpenLink: (ClipboardItem) -> Void
    private let onRevealInFinder: (ClipboardItem) -> Void
    private let onDelete: ([ClipboardItem]) -> Void
    private let onOpenSettings: () -> Void
    private let onAddToCollection: (ClipboardItem, UUID) -> Void
    private let onRemoveFromCollection: (ClipboardItem, UUID) -> Void
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
        onCopyPlainText: @escaping (ClipboardItem) -> Void,
        onOpenLink: @escaping (ClipboardItem) -> Void,
        onRevealInFinder: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping ([ClipboardItem]) -> Void,
        onOpenSettings: @escaping () -> Void,
        onAddToCollection: @escaping (ClipboardItem, UUID) -> Void,
        onRemoveFromCollection: @escaping (ClipboardItem, UUID) -> Void
    ) {
        self.historyStore = historyStore
        self.onSelect = onSelect
        self.onTogglePin = onTogglePin
        self.onCopy = onCopy
        self.onCopyPlainText = onCopyPlainText
        self.onOpenLink = onOpenLink
        self.onRevealInFinder = onRevealInFinder
        self.onDelete = onDelete
        self.onOpenSettings = onOpenSettings
        self.onAddToCollection = onAddToCollection
        self.onRemoveFromCollection = onRemoveFromCollection
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
        // The panel is designed as dark glass; force the window appearance so the SwiftUI
        // material doesn't render light (washed-out, low-contrast) in system light mode.
        panel.appearance = NSAppearance(named: .darkAqua)

        self.panel = panel
    }

    /// Builds the SwiftUI content on first use instead of during app launch. Instantiating
    /// the panel's view graph synchronously in applicationDidFinishLaunching showed up as
    /// launch hangs on memory-constrained Macs (Sentry PASTR-3T / PASTR-3S).
    private func installContentIfNeeded() {
        guard panel.contentView as? NSHostingView<PanelView> == nil else { return }
        let rootView = PanelView(
            viewModel: viewModel,
            onSelect: onSelect,
            onTogglePin: onTogglePin,
            onCopy: onCopy,
            onCopyPlainText: onCopyPlainText,
            onOpenLink: onOpenLink,
            onRevealInFinder: onRevealInFinder,
            onDelete: onDelete,
            onOpenSettings: onOpenSettings,
            onAddToCollection: onAddToCollection,
            onRemoveFromCollection: onRemoveFromCollection
        )
        panel.contentView = NSHostingView(rootView: rootView)
    }

    /// Builds the panel content once the app has settled, so the first open is still instant.
    func prewarm() {
        installContentIfNeeded()
    }

    deinit {
        stopClickMonitor()
        stopKeyMonitor()
    }

    func showPanel() {
        // Check if we should hide during screen sharing
        if !settingsStore.showDuringScreenSharing && isScreenBeingShared() {
            return
        }

        guard let screen = screenForCursor() else { return }
        settingsStore.updateDetectedDisplaySize(for: screen)
        let targetFrame = panelFrame(for: screen)
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -targetFrame.height - 12)

        installContentIfNeeded()
        viewModel.resetSelection()
        // PanelView doesn't observe every store (to avoid work while hidden), so refresh once on show.
        viewModel.objectWillChange.send()
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
        let displaySize = settingsStore.resolvedDisplaySize
        // Use dynamic height based on card height + header/padding
        let height: CGFloat = displaySize.cardHeight + 100
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

            // Check if a text field is focused - if so, let it handle most keys
            let isTextFieldFocused = self.isFirstResponderTextField()

            // Handle Cmd+A for select all (only when not in text field)
            if event.modifierFlags.contains(.command) && event.keyCode == 0 && !isTextFieldFocused {
                self.viewModel.selectAll()
                return nil
            }

            // Check if actively editing search text (field focused AND has text)
            let isEditingSearch = isTextFieldFocused && !self.viewModel.searchText.isEmpty

            switch event.keyCode {
            case 123: // Left arrow
                // Allow cursor movement when editing search, otherwise navigate items
                if isEditingSearch { return event }
                self.viewModel.selectPrevious()
                return nil
            case 124: // Right arrow
                // Allow cursor movement when editing search, otherwise navigate items
                if isEditingSearch { return event }
                self.viewModel.selectNext()
                return nil
            case 49: // Space
                // Allow space in text field for typing
                if isTextFieldFocused { return event }
                self.viewModel.togglePreviewForSelected()
                return nil
            case 36, 76: // Enter/Return
                // Allow Enter to work normally when search has text (to confirm search)
                // but also select item when not searching
                if isTextFieldFocused && !self.viewModel.searchText.isEmpty {
                    return event
                }
                if let item = self.viewModel.selectedItem {
                    self.onSelect(item)
                }
                return nil
            case 51, 117: // Delete (backspace) or Forward Delete
                // CRITICAL: Let text field handle backspace for editing search text
                if isTextFieldFocused { return event }
                let itemsToDelete = self.viewModel.selectedItems
                if !itemsToDelete.isEmpty {
                    self.onDelete(itemsToDelete)
                    self.viewModel.clearMultiSelection()
                }
                return nil
            case 53: // Escape
                // If searching, clear search first; otherwise hide panel
                if !self.viewModel.searchText.isEmpty {
                    self.viewModel.searchText = ""
                    return nil
                }
                self.hidePanel()
                return nil
            default:
                return event
            }
        }
    }

    private func isFirstResponderTextField() -> Bool {
        guard let firstResponder = panel.firstResponder else { return false }
        // Check if it's a text view (used by SwiftUI TextField) or text field
        return firstResponder is NSTextView || firstResponder is NSTextField
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
