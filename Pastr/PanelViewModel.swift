import Combine
import Foundation

final class PanelViewModel: ObservableObject {
    @Published var selectedSection: PanelSection = .history
    @Published var selectedIndex: Int = 0
    @Published var searchText: String = ""

    private let historyStore: ClipboardHistoryStore

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
    }

    var items: [ClipboardItem] {
        let baseItems = historyStore.items(for: selectedSection)
        guard !searchText.isEmpty else { return baseItems }
        let query = searchText.lowercased()
        return baseItems.filter { item in
            if let text = item.textContent?.lowercased(), text.contains(query) {
                return true
            }
            if let url = item.urlString?.lowercased(), url.contains(query) {
                return true
            }
            if let title = item.pinnedTitle?.lowercased(), title.contains(query) {
                return true
            }
            if let appName = item.sourceAppName?.lowercased(), appName.contains(query) {
                return true
            }
            if item.fileURLs.contains(where: { $0.lastPathComponent.lowercased().contains(query) }) {
                return true
            }
            return false
        }
    }

    var selectedItem: ClipboardItem? {
        let items = items
        guard !items.isEmpty, selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    func resetSelection() {
        selectedIndex = 0
        searchText = ""
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
