import AppKit
import QuartzCore
import SwiftUI

final class PanelWindowController {
    private let panel: PastrPanel
    private let historyStore: ClipboardHistoryStore
    private let onSelect: (ClipboardItem) -> Void
    private var clickMonitor: Any?

    var isPanelVisible: Bool {
        panel.isVisible
    }

    init(historyStore: ClipboardHistoryStore, onSelect: @escaping (ClipboardItem) -> Void) {
        self.historyStore = historyStore
        self.onSelect = onSelect

        let panel = PastrPanel(
            contentRect: .init(x: 0, y: 0, width: 900, height: 200),
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

        let rootView = PanelView(historyStore: historyStore, onSelect: onSelect)
        panel.contentView = NSHostingView(rootView: rootView)

        self.panel = panel
    }

    func showPanel() {
        guard let screen = screenForCursor() else { return }
        let targetFrame = panelFrame(for: screen)
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -targetFrame.height - 12)

        NSApp.activate(ignoringOtherApps: true)
        panel.setFrame(startFrame, display: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }

        startClickMonitor()
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        stopClickMonitor()

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
        let height: CGFloat = 200
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
}

final class PastrPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
