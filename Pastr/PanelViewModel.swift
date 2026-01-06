import Combine
import Foundation

final class PanelViewModel: ObservableObject {
    @Published var selectedSection: PanelSection = .history
    @Published var selectedIndex: Int = 0

    private let historyStore: ClipboardHistoryStore

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
    }

    var items: [ClipboardItem] {
        historyStore.items(for: selectedSection)
    }

    var selectedItem: ClipboardItem? {
        let items = items
        guard !items.isEmpty, selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    func resetSelection() {
        selectedIndex = 0
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            selectedIndex = index
        }
    }
}
