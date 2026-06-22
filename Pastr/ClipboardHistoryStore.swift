import AppKit
import Combine
import CoreData

final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    /// Threshold at which we warn users about potential performance impact
    static let performanceWarningThreshold = 15000

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var syncState: SyncState = .idle

    /// Returns true if history size may impact performance
    var isHistoryLarge: Bool {
        items.count >= Self.performanceWarningThreshold
    }

    private let settings = SettingsStore.shared
    private let persistence = HistoryPersistence()
    private let pinnedStore = PinnedStore.shared
    private let collectionStore = CollectionStore.shared
    private let enrichmentStore = AIEnrichmentStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        items = persistence.load()
        bindSettings()
        migrateToCollections()
        // Enrich any clips loaded from disk that don't yet have on-device intelligence.
        enrichmentStore.backfill(items)
    }

    /// Migrate from isPinned to collections system
    private func migrateToCollections() {
        let pinnedFingerprints = items.filter { $0.isPinned }.map { $0.fingerprint }
        collectionStore.migrateFromPinnedIfNeeded(pinnedFingerprints: pinnedFingerprints)
    }

    func add(_ item: ClipboardItem) {
        let itemToPersist: ClipboardItem
        if let existingIndex = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let existing = items[existingIndex]
            var updated = item
            updated.isPinned = existing.isPinned
            updated.pinnedTitle = existing.pinnedTitle
            items.remove(at: existingIndex)
            items.insert(updated, at: 0)
            itemToPersist = updated
        } else {
            items.insert(item, at: 0)
            itemToPersist = item
        }

        let removed = prune()
        persistence.save(items)
        syncUpsert(itemToPersist)
        syncRemove(removed)
        enrichmentStore.enrich(itemToPersist)
        removed.forEach { enrichmentStore.remove(fingerprint: $0.fingerprint) }
        SoundManager.playCopySound()
    }

    func items(for section: PanelSection) -> [ClipboardItem] {
        switch section {
        case .history:
            return items
        case .pinned:
            // Legacy support: items that are pinned OR in any collection
            return items.filter { $0.isPinned || collectionStore.isItemInAnyCollection(fingerprint: $0.fingerprint) }
        case .collection(let collectionId):
            guard let collection = collectionStore.collections.first(where: { $0.id == collectionId }) else {
                return []
            }
            return items.filter { collection.contains(fingerprint: $0.fingerprint) }
        case .tag(let tagId):
            let tagStore = TagStore.shared
            let itemsWithTag = tagStore.itemsWithTag(tagId)
            return items.filter { itemsWithTag.contains($0.fingerprint) }
        }
    }

    func items(for collection: Collection) -> [ClipboardItem] {
        items.filter { collection.contains(fingerprint: $0.fingerprint) }
    }

    /// Check if an item is in any collection
    func isInAnyCollection(_ item: ClipboardItem) -> Bool {
        collectionStore.isItemInAnyCollection(fingerprint: item.fingerprint)
    }

    /// Get collections containing an item
    func collections(for item: ClipboardItem) -> [Collection] {
        collectionStore.collections(containing: item.fingerprint)
    }

    func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        if updated.isPinned {
            updated.isPinned = false
            items[index] = updated
            syncUpsert(updated)
            SoundManager.playPinSound()
        } else {
            let currentPinned = items.filter { $0.isPinned }.count
            if currentPinned >= settings.pinLimit {
                NSSound.beep()
                return
            }
            updated.isPinned = true
            items[index] = updated
            syncUpsert(updated)
            SoundManager.playPinSound()
        }
        persistence.save(items)
    }

    // MARK: - Collection Management

    func addToCollection(_ item: ClipboardItem, collectionId: UUID) {
        collectionStore.addItem(fingerprint: item.fingerprint, to: collectionId)
        SoundManager.playPinSound()
    }

    func removeFromCollection(_ item: ClipboardItem, collectionId: UUID) {
        collectionStore.removeItem(fingerprint: item.fingerprint, from: collectionId)
        SoundManager.playPinSound()
    }

    func toggleCollection(_ item: ClipboardItem, collectionId: UUID) {
        let collections = collectionStore.collections(containing: item.fingerprint)
        if collections.contains(where: { $0.id == collectionId }) {
            removeFromCollection(item, collectionId: collectionId)
        } else {
            addToCollection(item, collectionId: collectionId)
        }
    }

    func updatePinnedTitle(for item: ClipboardItem, title: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.pinnedTitle = title
        items[index] = updated
        syncUpsert(updated)
        persistence.save(items)
    }

    func clearUnpinnedItems() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        persistence.save(items)
        syncRemove(removed)
        enrichmentStore.prune(keeping: Set(items.map { $0.fingerprint }))
    }

    func delete(_ item: ClipboardItem) {
        syncRemove([item])
        items.removeAll { $0.id == item.id }
        persistence.save(items)
        pruneEnrichmentIfOrphaned(item.fingerprint)
    }

    func delete(_ itemsToDelete: [ClipboardItem]) {
        let idsToDelete = Set(itemsToDelete.map { $0.id })
        syncRemove(itemsToDelete)
        items.removeAll { idsToDelete.contains($0.id) }
        persistence.save(items)
        itemsToDelete.forEach { pruneEnrichmentIfOrphaned($0.fingerprint) }
    }

    /// Remove enrichment for a fingerprint only if no remaining clip uses it.
    private func pruneEnrichmentIfOrphaned(_ fingerprint: String) {
        guard !items.contains(where: { $0.fingerprint == fingerprint }) else { return }
        enrichmentStore.remove(fingerprint: fingerprint)
    }

    func mergeCloudItems(_ cloudItems: [ClipboardItem]) {
        for cloudItem in cloudItems {
            if let index = items.firstIndex(where: { $0.fingerprint == cloudItem.fingerprint }) {
                items[index] = cloudItem
            } else {
                items.insert(cloudItem, at: 0)
            }
        }
        items.sort { $0.createdAt > $1.createdAt }
        persistence.save(items)
    }

    func replaceAll(with newItems: [ClipboardItem]) {
        items = newItems.sorted { $0.createdAt > $1.createdAt }
        persistence.save(items)
        if settings.iCloudSyncEnabled {
            try? pinnedStore.removeAll()
            syncAllToCloud()
        }
    }

    func syncAllToCloud() {
        guard settings.iCloudSyncEnabled else { return }
        for item in items {
            try? pinnedStore.upsert(item)
        }
    }

    func syncNow() {
        guard settings.iCloudSyncEnabled else { return }
        syncState = .syncing
        let localItems = items
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let cloudItems = try self.pinnedStore.fetchAll()
                DispatchQueue.main.async {
                    self.mergeCloudItems(cloudItems)
                }
                for item in localItems {
                    try self.pinnedStore.upsert(item)
                }
                DispatchQueue.main.async {
                    self.syncState = .success
                }
            } catch {
                DispatchQueue.main.async {
                    self.syncState = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    func clearSyncState() {
        syncState = .idle
    }

    @discardableResult
    private func prune() -> [ClipboardItem] {
        var removed: [ClipboardItem] = []
        if !settings.historyUnlimited {
            let cutoff = Calendar.current.date(byAdding: .day, value: -settings.historyMaxDays, to: Date())
            if let cutoff {
                let expired = items.filter { !$0.isPinned && $0.createdAt < cutoff }
                removed.append(contentsOf: expired)
                items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
            }

            // Only prune by item count if a limit is set (0 = unlimited)
            if settings.historyMaxItems > 0 && items.count > settings.historyMaxItems {
                let pinnedCount = items.filter { $0.isPinned }.count
                let allowedUnpinned = max(settings.historyMaxItems - pinnedCount, 0)
                var trimmed: [ClipboardItem] = []
                var unpinnedCount = 0
                for item in items {
                    if item.isPinned {
                        trimmed.append(item)
                    } else if unpinnedCount < allowedUnpinned {
                        trimmed.append(item)
                        unpinnedCount += 1
                    }
                }
                let keptIds = Set(trimmed.map { $0.id })
                let trimmedOut = items.filter { !keptIds.contains($0.id) }
                removed.append(contentsOf: trimmedOut)
                items = trimmed
            }
        }
        return removed
    }

    private func bindSettings() {
        Publishers.CombineLatest3(settings.$historyMaxItems, settings.$historyMaxDays, settings.$historyUnlimited)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                let removed = self.prune()
                self.persistence.save(self.items)
                self.syncRemove(removed)
            }
            .store(in: &cancellables)

        settings.$iCloudSyncEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, enabled else { return }
                if let cloudItems = try? self.pinnedStore.fetchAll() {
                    self.mergeCloudItems(cloudItems)
                }
                self.syncAllToCloud()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange,
            object: pinnedStore.remoteChangeNotificationObject
        )
        .sink { [weak self] _ in
            self?.mergeLatestCloudItems()
        }
        .store(in: &cancellables)
    }

    private func mergeLatestCloudItems() {
        guard settings.iCloudSyncEnabled else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let cloudItems = try? self.pinnedStore.fetchAll() else {
                return
            }

            DispatchQueue.main.async {
                self.mergeCloudItems(cloudItems)
            }
        }
    }

    private func syncUpsert(_ item: ClipboardItem) {
        guard settings.iCloudSyncEnabled else { return }
        try? pinnedStore.upsert(item)
    }

    private func syncRemove(_ items: [ClipboardItem]) {
        guard settings.iCloudSyncEnabled else { return }
        for item in items {
            try? pinnedStore.remove(fingerprint: item.fingerprint)
        }
    }
}

enum SyncState: Equatable {
    case idle
    case syncing
    case success
    case failed(message: String)
}
