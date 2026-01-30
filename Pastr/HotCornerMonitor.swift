import AppKit
import Combine
import Foundation

/// Monitors mouse position to trigger panel when cursor enters a screen corner
final class HotCornerMonitor: ObservableObject {
    static let shared = HotCornerMonitor()

    enum Corner: String, CaseIterable, Codable {
        case topLeft = "Top Left"
        case topRight = "Top Right"
        case bottomLeft = "Bottom Left"
        case bottomRight = "Bottom Right"
        case disabled = "Disabled"

        var isEnabled: Bool {
            self != .disabled
        }
    }

    @Published private(set) var isHovering: Bool = false

    private var timer: DispatchSourceTimer?
    private var hoverStartTime: Date?
    private var onTrigger: (() -> Void)?
    private let settings = SettingsStore.shared

    /// The size of the corner detection zone
    private let cornerSize: CGFloat = 10

    /// Delay before triggering (prevents accidental triggers)
    private var triggerDelay: TimeInterval {
        settings.hotCornerDelay
    }

    private init() {}

    func setHandler(_ handler: @escaping () -> Void) {
        onTrigger = handler
    }

    func start() {
        stop()
        guard settings.hotCorner.isEnabled else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.checkMousePosition()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isHovering = false
        hoverStartTime = nil
    }

    func restart() {
        stop()
        start()
    }

    private func checkMousePosition() {
        guard let screen = NSScreen.main else { return }
        let mouseLocation = NSEvent.mouseLocation
        let corner = settings.hotCorner

        let isInCorner = isMouseInCorner(mouseLocation, corner: corner, screen: screen)

        if isInCorner {
            if !isHovering {
                // Just entered corner
                isHovering = true
                hoverStartTime = Date()
            } else if let startTime = hoverStartTime {
                // Check if we've been hovering long enough
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= triggerDelay {
                    // Trigger!
                    hoverStartTime = nil
                    isHovering = false
                    onTrigger?()
                }
            }
        } else {
            // Left corner
            isHovering = false
            hoverStartTime = nil
        }
    }

    private func isMouseInCorner(_ location: NSPoint, corner: Corner, screen: NSScreen) -> Bool {
        let frame = screen.frame

        switch corner {
        case .topLeft:
            return location.x <= frame.minX + cornerSize &&
                   location.y >= frame.maxY - cornerSize

        case .topRight:
            return location.x >= frame.maxX - cornerSize &&
                   location.y >= frame.maxY - cornerSize

        case .bottomLeft:
            return location.x <= frame.minX + cornerSize &&
                   location.y <= frame.minY + cornerSize

        case .bottomRight:
            return location.x >= frame.maxX - cornerSize &&
                   location.y <= frame.minY + cornerSize

        case .disabled:
            return false
        }
    }
}
