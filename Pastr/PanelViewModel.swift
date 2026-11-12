import Combine
import Foundation

final class PanelViewModel: ObservableObject {
    @Published var selectedSection: PanelSection = .history {
        didSet {
            guard oldValue != selectedSection else { return }
            searchCriteriaDidChange()
        }
    }
    @Published var selectedIndex: Int = 0
    @Published var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchCriteriaDidChange()
        }
    }
    @Published var selectedItemIds: Set<UUID> = []
    @Published private(set) var previewItem: ClipboardItem?
    @Published var showingCreateCollection: Bool = false
    @Published private(set) var items: [ClipboardItem] = []

    private let historyStore: ClipboardHistoryStore
    private let collectionStore = CollectionStore.shared
    private let settings = SettingsStore.shared
    private let enrichmentStore = AIEnrichmentStore.shared
    private var previewSource: PreviewSource?
    private var hoverWorkItem: DispatchWorkItem?
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
        items = historyStore.items(for: selectedSection)
        // Invalidate cache when history changes
        // @Published emits in willSet; hop to the next main-loop turn so
        // `historyStore.items(for:)` reads the new value, not the previous one.
        historyStore.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.searchSourceDidChange()
            }
            .store(in: &cancellables)

        // Invalidate cache when collections change
        collectionStore.$collections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.searchSourceDidChange()
            }
            .store(in: &cancellables)

        // Tag sections filter by tag assignments, so refresh when they change.
        TagStore.shared.$itemTags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, case .tag = self.selectedSection else { return }
                self.searchSourceDidChange()
            }
            .store(in: &cancellables)

        enrichmentStore.$enrichments
            .sink { [weak self] _ in
                guard self?.searchText.isEmpty == false else { return }
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
        searchTask?.cancel()
    }

    private func searchCriteriaDidChange() {
        scheduleSearch()
    }

    private func searchSourceDidChange() {
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText
        let section = selectedSection
        let baseItems = historyStore.items(for: section)
        guard !query.isEmpty else {
            // ClipboardItem equality is cheap (no payload compare); avoid no-op publishes.
            if items != baseItems {
                items = baseItems
            }
            return
        }

        // Copy-on-write capture; lookups are built/consulted off the main thread in the search.
        let enrichments = enrichmentStore.enrichments
        let semanticSearchEnabled = settings.semanticSearchEnabled
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let matches = await Self.searchItems(
                query: query,
                baseItems: baseItems,
                enrichments: enrichments,
                semanticSearchEnabled: semanticSearchEnabled
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.searchText == query,
                      self.selectedSection == section else { return }
                if self.items != matches {
                    self.items = matches
                }
            }
        }
    }

    private nonisolated static func searchItems(
        query: String,
        baseItems: [ClipboardItem],
        enrichments: [String: AIEnrichment],
        semanticSearchEnabled: Bool
    ) async -> [ClipboardItem] {
        let worker = Task.detached(priority: .userInitiated) { () -> [ClipboardItem] in
            var literalMatches: [ClipboardItem] = []
            literalMatches.reserveCapacity(min(baseItems.count, 256))
            for (index, item) in baseItems.enumerated() {
                if index.isMultiple(of: 64), Task.isCancelled { return [] }
                if item.textContent?.localizedCaseInsensitiveContains(query) == true {
                    literalMatches.append(item)
                    continue
                }
                let matchesMetadata = item.urlString?.localizedCaseInsensitiveContains(query) == true
                    || item.pinnedTitle?.localizedCaseInsensitiveContains(query) == true
                    || item.sourceAppName?.localizedCaseInsensitiveContains(query) == true
                    || item.fileURLs.contains {
                        $0.lastPathComponent.localizedCaseInsensitiveContains(query)
                    }
                    || enrichments[item.fingerprint]?.searchableText?.localizedCaseInsensitiveContains(query) == true
                if matchesMetadata {
                    literalMatches.append(item)
                }
            }

            guard semanticSearchEnabled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3,
                  !Task.isCancelled,
                  let queryVector = SemanticIndex.embedQuery(query) else {
                return literalMatches
            }

            let literalIds = Set(literalMatches.map { $0.id })
            var semanticMatches: [(item: ClipboardItem, score: Float)] = []
            for (index, item) in baseItems.enumerated() where !literalIds.contains(item.id) {
                if index.isMultiple(of: 64), Task.isCancelled { return [] }
                guard let vector = enrichments[item.fingerprint]?.embedding else { continue }
                let score = SemanticIndex.similarity(queryVector, vector)
                if score >= SemanticIndex.matchThreshold {
                    semanticMatches.append((item, score))
                }
            }
            semanticMatches.sort { $0.score > $1.score }
            literalMatches.append(contentsOf: semanticMatches.map(\.item))
            return literalMatches
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
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
