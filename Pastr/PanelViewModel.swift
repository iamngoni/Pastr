import Combine
import Foundation

final class PanelViewModel: ObservableObject {
    @Published var selectedSection: PanelSection = .history {
        didSet { searchCriteriaDidChange() }
    }
    @Published var selectedIndex: Int = 0
    @Published var searchText: String = "" {
        didSet { searchCriteriaDidChange() }
    }
    @Published var selectedItemIds: Set<UUID> = []
    @Published private(set) var previewItem: ClipboardItem?
    @Published var showingCreateCollection: Bool = false
    @Published private var semanticMatchFingerprints: [String] = []

    private let historyStore: ClipboardHistoryStore
    private let collectionStore = CollectionStore.shared
    private let settings = SettingsStore.shared
    private let enrichmentStore = AIEnrichmentStore.shared
    private var previewSource: PreviewSource?
    private var hoverWorkItem: DispatchWorkItem?
    private var semanticSearchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Cached filtered items to avoid recomputing on every access during layout
    private var cachedFilteredItems: [ClipboardItem]?
    private var cachedSearchText: String = ""
    private var cachedSection: PanelSection = .history
    private var semanticResultQuery = ""
    private var semanticResultSection: PanelSection = .history

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
        // Invalidate cache when history changes
        historyStore.$items
            .sink { [weak self] _ in
                self?.searchSourceDidChange()
            }
            .store(in: &cancellables)

        // Invalidate cache when collections change
        collectionStore.$collections
            .sink { [weak self] _ in
                self?.searchSourceDidChange()
            }
            .store(in: &cancellables)

        enrichmentStore.$enrichments
            .sink { [weak self] _ in
                self?.searchSourceDidChange()
            }
            .store(in: &cancellables)

        settings.$semanticSearchEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.searchSourceDidChange()
            }
            .store(in: &cancellables)
    }

    deinit {
        hoverWorkItem?.cancel()
        semanticSearchTask?.cancel()
    }

    private func invalidateFilteredItems() {
        cachedFilteredItems = nil
    }

    private func searchCriteriaDidChange() {
        invalidateFilteredItems()
        scheduleSemanticSearch()
    }

    private func searchSourceDidChange() {
        invalidateFilteredItems()
        scheduleSemanticSearch()
    }

    private func scheduleSemanticSearch() {
        semanticSearchTask?.cancel()
        semanticSearchTask = nil
        semanticMatchFingerprints = []
        semanticResultQuery = ""

        let query = searchText
        let section = selectedSection
        guard settings.semanticSearchEnabled,
              query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
            return
        }
        let baseItems = historyStore.items(for: section)

        semanticSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            let matches = await self.enrichmentStore.semanticMatches(for: query, among: baseItems)
            guard !Task.isCancelled,
                  self.searchText == query,
                  self.selectedSection == section else { return }
            self.semanticResultQuery = query
            self.semanticResultSection = section
            self.semanticMatchFingerprints = matches.map(\.fingerprint)
            self.invalidateFilteredItems()
        }
    }

    var items: [ClipboardItem] {
        // Return cached results if valid
        if let cached = cachedFilteredItems,
           cachedSearchText == searchText,
           cachedSection == selectedSection {
            return cached
        }

        // Compute and cache
        let baseItems = historyStore.items(for: selectedSection)
        let result: [ClipboardItem]

        if searchText.isEmpty {
            result = baseItems
        } else {
            let query = searchText
            // Exact/substring matches across clip text, metadata and OCR'd image text.
            var literalMatches = baseItems.filter { item in
                if item.textContent?.localizedCaseInsensitiveContains(query) == true {
                    return true
                }
                if item.urlString?.localizedCaseInsensitiveContains(query) == true {
                    return true
                }
                if item.pinnedTitle?.localizedCaseInsensitiveContains(query) == true {
                    return true
                }
                if item.sourceAppName?.localizedCaseInsensitiveContains(query) == true {
                    return true
                }
                if item.fileURLs.contains(where: { $0.lastPathComponent.localizedCaseInsensitiveContains(query) }) {
                    return true
                }
                if enrichmentStore.searchableText(for: item.fingerprint)?.localizedCaseInsensitiveContains(query) == true {
                    return true
                }
                return false
            }

            // Semantic ("search by meaning") matches appended after literal hits, ranked by
            // similarity and de-duplicated. Only kicks in when enabled and available.
            let literalIds = Set(literalMatches.map { $0.id })
            if semanticResultQuery == searchText,
               semanticResultSection == selectedSection,
               !semanticMatchFingerprints.isEmpty {
                let byFingerprint = Dictionary(baseItems.map { ($0.fingerprint, $0) }, uniquingKeysWith: { a, _ in a })
                for fingerprint in semanticMatchFingerprints {
                    guard let item = byFingerprint[fingerprint], !literalIds.contains(item.id) else { continue }
                    literalMatches.append(item)
                }
            }
            result = literalMatches
        }

        cachedFilteredItems = result
        cachedSearchText = searchText
        cachedSection = selectedSection
        return result
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
            return selectedItem?.id == item.id
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
        guard settings.enableQuickPreview else { return }
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
