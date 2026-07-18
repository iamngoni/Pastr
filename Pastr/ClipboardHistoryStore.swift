import AppKit
import Combine
import CoreData

final class ClipboardHistoryStore: ObservableObject {
    private enum InitialLoadPolicy {
        case mergeAll
        case pinnedOnly
        case discard
    }

    static let shared = ClipboardHistoryStore()

    /// Threshold at which we warn users about potential performance impact
    static let performanceWarningThreshold = 15000

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var syncState: SyncState = .idle

    /// Returns true if history size may impact performance
    var isHistoryLarge: Bool {
        items.count >= Self.performanceWarningThreshold
    }

    private lazy var settings = SettingsStore.shared
    private let persistence = HistoryPersistence()
    private lazy var pinnedStore = PinnedStore.shared
    private lazy var collectionStore = CollectionStore.shared
    private lazy var enrichmentStore = AIEnrichmentStore.shared
    private let cloudSyncQueue = DispatchQueue(label: "pastr.cloud-sync", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var hasLoadedHistory = false
    private var initialLoadPolicy: InitialLoadPolicy = .mergeAll
    private var locallyDeletedFingerprints: Set<String> = []

    init() {
        persistence.loadAsync { [weak self] loadedItems in
            DispatchQueue.main.async {
                self?.finishInitialLoad(loadedItems)
            }
        }
    }

    private func finishInitialLoad(_ loadedItems: [ClipboardItem]) {
        let itemsToMerge: [ClipboardItem]
        switch initialLoadPolicy {
        case .mergeAll:
            itemsToMerge = loadedItems
        case .pinnedOnly:
            itemsToMerge = loadedItems.filter(\.isPinned)
        case .discard:
            itemsToMerge = []
        }

        if initialLoadPolicy != .discard {
            var mergedByFingerprint = Dictionary(
                itemsToMerge.map { ($0.fingerprint, $0) },
                uniquingKeysWith: { existing, candidate in
                    candidate.createdAt > existing.createdAt ? candidate : existing
                }
            )
            for liveItem in items {
                var item = liveItem
                if let loadedItem = mergedByFingerprint[liveItem.fingerprint] {
                    item.isPinned = liveItem.isPinned || loadedItem.isPinned
                    item.pinnedTitle = liveItem.pinnedTitle ?? loadedItem.pinnedTitle
                }
                mergedByFingerprint[item.fingerprint] = item
            }
            items = mergedByFingerprint.values.sorted { $0.createdAt > $1.createdAt }
        }

        hasLoadedHistory = true
        let prunedItems = prune()
        let currentFingerprints = Set(items.map(\.fingerprint))
        let excludedByPolicy = loadedItems.filter { !currentFingerprints.contains($0.fingerprint) }
        recordLocalDeletions(excludedByPolicy + prunedItems)
        persistHistory()
        syncRemove(excludedByPolicy + prunedItems)
        bindSettings()
        migrateToCollections()
        // Enrich any clips loaded from disk that don't yet have on-device intelligence.
        enrichmentStore.backfill(items)
    }

    private func persistHistory() {
        guard hasLoadedHistory else { return }
        persistence.save(items)
    }

    /// Migrate from isPinned to collections system
    private func migrateToCollections() {
        let pinnedFingerprints = items.filter { $0.isPinned }.map { $0.fingerprint }
        collectionStore.migrateFromPinnedIfNeeded(pinnedFingerprints: pinnedFingerprints)
    }

    func add(_ item: ClipboardItem) {
        locallyDeletedFingerprints.remove(item.fingerprint)
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
        persistHistory()
        syncUpsert(itemToPersist)
        syncRemove(removed)
        enrichmentStore.enrich(itemToPersist)
        removed.forEach { pruneDerivedDataIfOrphaned($0.fingerprint) }
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
        persistHistory()
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
        persistHistory()
    }

    func clearUnpinnedItems() {
        if !hasLoadedHistory, initialLoadPolicy != .discard {
            initialLoadPolicy = .pinnedOnly
        }
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        persistHistory()
        recordLocalDeletions(removed)
        syncRemove(removed)
        if hasLoadedHistory {
            enrichmentStore.prune(keeping: Set(items.map { $0.fingerprint }))
            removed.forEach { pruneCachesIfOrphaned($0.fingerprint) }
        }
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persistHistory()
        recordLocalDeletions([item])
        syncRemove([item])
        pruneDerivedDataIfOrphaned(item.fingerprint)
    }

    func delete(_ itemsToDelete: [ClipboardItem]) {
        let idsToDelete = Set(itemsToDelete.map { $0.id })
        items.removeAll { idsToDelete.contains($0.id) }
        persistHistory()
        recordLocalDeletions(itemsToDelete)
        syncRemove(itemsToDelete)
        itemsToDelete.forEach { pruneDerivedDataIfOrphaned($0.fingerprint) }
    }

    /// Remove derived data for a fingerprint only if no remaining clip uses it.
    private func pruneDerivedDataIfOrphaned(_ fingerprint: String) {
        guard !items.contains(where: { $0.fingerprint == fingerprint }) else { return }
        enrichmentStore.remove(fingerprint: fingerprint)
        pruneCachesIfOrphaned(fingerprint)
    }

    private func pruneCachesIfOrphaned(_ fingerprint: String) {
        guard !items.contains(where: { $0.fingerprint == fingerprint }) else { return }
        AttributedStringCache.shared.removeAttributedString(for: fingerprint)
        ClipboardImageCache.shared.removeImage(for: fingerprint)
    }

    func mergeCloudItems(_ cloudItems: [ClipboardItem]) {
        for cloudItem in cloudItems where !locallyDeletedFingerprints.contains(cloudItem.fingerprint) {
            if let index = items.firstIndex(where: { $0.fingerprint == cloudItem.fingerprint }) {
                items[index] = cloudItem
            } else {
                items.insert(cloudItem, at: 0)
            }
        }
        items.sort { $0.createdAt > $1.createdAt }
        persistHistory()
    }

    func replaceAll(with newItems: [ClipboardItem]) {
        if !hasLoadedHistory { initialLoadPolicy = .discard }
        let oldFingerprints = Set(items.map { $0.fingerprint })
        items = newItems.sorted { $0.createdAt > $1.createdAt }
        persistHistory()
        let currentFingerprints = Set(items.map { $0.fingerprint })
        locallyDeletedFingerprints.formUnion(oldFingerprints.subtracting(currentFingerprints))
        locallyDeletedFingerprints.subtract(currentFingerprints)
        oldFingerprints.subtracting(currentFingerprints).forEach { fingerprint in
            enrichmentStore.remove(fingerprint: fingerprint)
            AttributedStringCache.shared.removeAttributedString(for: fingerprint)
            ClipboardImageCache.shared.removeImage(for: fingerprint)
        }
        if settings.iCloudSyncEnabled, pinnedStore.isCloudSyncAvailable {
            let replacement = items
            cloudSyncQueue.async { [pinnedStore] in
                try? pinnedStore.replaceAll(with: replacement)
            }
        }
    }

    func syncAllToCloud() {
        guard settings.iCloudSyncEnabled, pinnedStore.isCloudSyncAvailable else { return }
        let localItems = items
        cloudSyncQueue.async { [pinnedStore] in
            try? pinnedStore.upsert(localItems)
        }
    }

    func syncNow() {
        guard settings.iCloudSyncEnabled else { return }
        guard pinnedStore.isCloudSyncAvailable else {
            syncState = .failed(message: "iCloud sync is unavailable in this build.")
            return
        }
        syncState = .syncing
        cloudSyncQueue.async { [weak self] in
            guard let self else { return }
            do {
                let cloudItems = try self.pinnedStore.fetchAll()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.mergeCloudItems(cloudItems)
                    let mergedItems = self.items
                    self.cloudSyncQueue.async { [weak self] in
                        guard let self else { return }
                        do {
                            try self.pinnedStore.upsert(mergedItems)
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
                self.persistHistory()
                self.recordLocalDeletions(removed)
                self.syncRemove(removed)
            }
            .store(in: &cancellables)

        settings.$iCloudSyncEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, enabled else { return }
                self.syncNow()
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
        guard settings.iCloudSyncEnabled, pinnedStore.isCloudSyncAvailable else { return }

        cloudSyncQueue.async { [weak self] in
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
        guard settings.iCloudSyncEnabled, pinnedStore.isCloudSyncAvailable else { return }
        cloudSyncQueue.async { [pinnedStore] in
            try? pinnedStore.upsert(item)
        }
    }

    private func syncRemove(_ items: [ClipboardItem]) {
        guard settings.iCloudSyncEnabled, pinnedStore.isCloudSyncAvailable else { return }
        let currentFingerprints = Set(self.items.map(\.fingerprint))
        let fingerprints = Array(Set(items.map(\.fingerprint)).subtracting(currentFingerprints))
        guard !fingerprints.isEmpty else { return }
        cloudSyncQueue.async { [pinnedStore] in
            try? pinnedStore.remove(fingerprints: fingerprints)
        }
    }

    private func recordLocalDeletions(_ removedItems: [ClipboardItem]) {
        let currentFingerprints = Set(items.map(\.fingerprint))
        for fingerprint in Set(removedItems.map(\.fingerprint)).subtracting(currentFingerprints) {
            locallyDeletedFingerprints.insert(fingerprint)
        }
    }
}

enum SyncState: Equatable {
    case idle
    case syncing
    case success
    case failed(message: String)
}
