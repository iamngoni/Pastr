import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {
    init(onFinish: @escaping () -> Void) {
        let view = OnboardingView(onFinish: onFinish)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.center()
        window.title = "Welcome to Pastr"
        window.contentView = hosting
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
