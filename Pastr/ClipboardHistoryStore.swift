import AppKit
import Combine

final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let maxItemsDefault = 100
    private let maxAgeDaysDefault = 30

    func add(_ item: ClipboardItem) {
        if items.contains(where: { $0.fingerprint == item.fingerprint }) {
            return
        }

        items.insert(item, at: 0)
        prune()
    }

    func items(for section: PanelSection) -> [ClipboardItem] {
        switch section {
        case .history:
            return items.filter { !$0.isPinned }
        case .pinned:
            return items.filter { $0.isPinned }
        }
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDaysDefault, to: Date())
        if let cutoff {
            items.removeAll { $0.createdAt < cutoff }
        }

        if items.count > maxItemsDefault {
            items = Array(items.prefix(maxItemsDefault))
        }
    }
}
