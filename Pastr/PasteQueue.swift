import Combine
import Foundation

/// Manages sequential copy/paste operations.
/// When queue mode is active, copied items are added to a queue
/// and can be pasted in sequence (FIFO order).
final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentIndex: Int = 0

    /// Number of items remaining to paste
    var remainingCount: Int {
        max(0, items.count - currentIndex)
    }

    /// Whether there are items left to paste
    var hasItems: Bool {
        currentIndex < items.count
    }

    /// The next item that will be pasted
    var nextItem: ClipboardItem? {
        guard hasItems else { return nil }
        return items[currentIndex]
    }

    private init() {}

    // MARK: - Queue Control

    /// Start queue mode. Subsequent copies will be added to the queue.
    func start() {
        guard !isActive else { return }
        isActive = true
        items = []
        currentIndex = 0
    }

    /// Stop queue mode and clear all items.
    func stop() {
        isActive = false
        items = []
        currentIndex = 0
    }

    /// Toggle queue mode on/off.
    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Item Management

    /// Add an item to the queue. Only works when queue mode is active.
    func enqueue(_ item: ClipboardItem) {
        guard isActive else { return }
        items.append(item)
    }

    /// Get the next item to paste and advance the index.
    /// Returns nil if no items left.
    func dequeue() -> ClipboardItem? {
        guard hasItems else {
            // Auto-stop when queue is exhausted
            stop()
            return nil
        }
        let item = items[currentIndex]
        currentIndex += 1

        // Auto-stop when queue is exhausted
        if !hasItems {
            stop()
        }

        return item
    }

    /// Peek at the next item without advancing.
    func peek() -> ClipboardItem? {
        nextItem
    }

    /// Reset the queue to paste from the beginning again.
    func reset() {
        currentIndex = 0
    }

    /// Clear all items but keep queue mode active.
    func clear() {
        items = []
        currentIndex = 0
    }

    /// Remove a specific item from the queue.
    func remove(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
        // Adjust currentIndex if needed
        if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        }
    }
}
