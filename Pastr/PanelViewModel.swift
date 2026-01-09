import Combine
import Foundation

final class PanelViewModel: ObservableObject {
    @Published var selectedSection: PanelSection = .history
    @Published var selectedIndex: Int = 0
    @Published var searchText: String = ""
    @Published var selectedItemIds: Set<UUID> = []
    @Published private(set) var previewItem: ClipboardItem?

    private let historyStore: ClipboardHistoryStore
    private var previewSource: PreviewSource?
    private var hoverWorkItem: DispatchWorkItem?

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

    var selectedItems: [ClipboardItem] {
        if selectedItemIds.isEmpty, let item = selectedItem {
            return [item]
        }
        return items.filter { selectedItemIds.contains($0.id) }
    }

    var hasMultipleSelection: Bool {
        selectedItemIds.count > 1
    }

    func isSelected(_ item: ClipboardItem) -> Bool {
        if selectedItemIds.isEmpty {
            return items.firstIndex(where: { $0.id == item.id }) == selectedIndex
        }
        return selectedItemIds.contains(item.id)
    }

    func resetSelection() {
        selectedIndex = 0
        searchText = ""
        selectedItemIds.removeAll()
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
        selectedItemIds.removeAll()
        if previewSource == .explicit {
            previewItem = selectedItem
        }
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        selectedItemIds.removeAll()
        if previewSource == .explicit {
            previewItem = selectedItem
        }
    }

    func selectItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            selectedIndex = index
            selectedItemIds.removeAll()
        }
    }

    func toggleSelection(for item: ClipboardItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            // If first multi-select, add current single selection too
            if selectedItemIds.isEmpty, let current = selectedItem {
                selectedItemIds.insert(current.id)
            }
            selectedItemIds.insert(item.id)
        }
    }

    func selectAll() {
        selectedItemIds = Set(items.map { $0.id })
    }

    func clearMultiSelection() {
        selectedItemIds.removeAll()
    }

    func showPreview(_ item: ClipboardItem, source: PreviewSource) {
        previewSource = source
        previewItem = item
    }

    func clearPreview() {
        previewSource = nil
        previewItem = nil
    }

    func togglePreviewForSelected() {
        guard let item = selectedItem else { return }
        if previewSource == .explicit, previewItem?.id == item.id {
            clearPreview()
        } else {
            showPreview(item, source: .explicit)
        }
    }

    func hoverPreview(for item: ClipboardItem, isHovering: Bool) {
        guard previewSource != .explicit else { return }

        if isHovering {
            hoverWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.showPreview(item, source: .hover)
            }
            hoverWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        } else {
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
            if previewSource == .hover, previewItem?.id == item.id {
                clearPreview()
            }
        }
    }
}

enum PreviewSource {
    case hover
    case explicit
}
