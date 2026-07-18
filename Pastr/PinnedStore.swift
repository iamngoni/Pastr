import AppKit
import CoreData
import Security

final class PinnedStore {
    static let shared = PinnedStore()

    private static let cloudContainerIdentifier = "iCloud.za.co.codecraftsolutions.Pastr"

    private let container: NSPersistentContainer
    let isCloudSyncAvailable: Bool
    private let migrationKey = "cloudHistoryPinnedMigrationCompleted"

    var remoteChangeNotificationObject: NSPersistentStoreCoordinator {
        container.persistentStoreCoordinator
    }

    private init() {
        let useCloudKit = !Self.isRunningTests && Self.hasCloudKitEntitlement
        isCloudSyncAvailable = useCloudKit

        if useCloudKit {
            container = NSPersistentCloudKitContainer(name: "Pastr")
        } else {
            container = NSPersistentContainer(name: "Pastr")
        }

        let description = container.persistentStoreDescriptions.first
        if useCloudKit {
            description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudContainerIdentifier
            )
            description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description?.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
        } else {
            // Test hosts and unsigned local builds do not have the CloudKit entitlement.
            // Keep their sync backing store isolated from both CloudKit and user data.
            description?.type = NSInMemoryStoreType
        }

        container.loadPersistentStores { _, error in
            if let error {
                NSLog("PinnedStore load error: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }

    private static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let identifiers = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              ) as? [String],
              let services = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-services" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return identifiers.contains(cloudContainerIdentifier) && services.contains("CloudKit")
    }

    func fetchAll() throws -> [ClipboardItem] {
        let context = makeBackgroundContext()
        var fetched: [ClipboardItem] = []
        var fetchError: Error?

        context.performAndWait {
            let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchBatchSize = 200
            request.returnsObjectsAsFaults = false
            do {
                let results = try context.fetch(request)
                let shouldMigratePinned = !UserDefaults.standard.bool(forKey: migrationKey)
                var needsSave = false
                fetched = results.compactMap { clip in
                    guard let id = clip.id,
                          let createdAt = clip.createdAt,
                          let type = clip.type,
                          let fingerprint = clip.fingerprint else {
                        return nil
                    }
                    let isPinned: Bool
                    if shouldMigratePinned {
                        isPinned = true
                        clip.isPinned = true
                        needsSave = true
                    } else {
                        isPinned = clip.isPinned
                    }
                    return ClipboardItem(
                        id: id,
                        createdAt: createdAt,
                        type: ClipboardItemType(rawValue: type) ?? .other,
                        textContent: clip.textContent,
                        rtfData: clip.rtfData,
                        imageData: clip.imageData,
                        urlString: clip.urlString,
                        fileURLs: clip.fileBookmarkData.flatMap { Self.resolveFileBookmarks($0) } ?? [],
                        sourceAppBundleId: clip.sourceAppBundleId,
                        sourceAppName: clip.sourceAppName,
                        isPinned: isPinned,
                        pinnedTitle: clip.pinnedTitle,
                        typesData: Self.decodeTypesData(clip.typesArchive),
                        fingerprint: fingerprint
                    )
                }
                if shouldMigratePinned, needsSave {
                    try save(context: context)
                    UserDefaults.standard.set(true, forKey: migrationKey)
                } else if shouldMigratePinned {
                    UserDefaults.standard.set(true, forKey: migrationKey)
                }
            } catch {
                fetchError = error
            }
        }

        if let fetchError {
            throw fetchError
        }
        return fetched
    }

    func upsert(_ item: ClipboardItem) throws {
        try upsert([item])
    }

    /// Apply a history snapshot in one Core Data transaction. This avoids creating a context,
    /// fetching, serializing large blobs, and checkpointing SQLite once per clip.
    func upsert(_ items: [ClipboardItem]) throws {
        guard !items.isEmpty else { return }
        let uniqueItems = Array(
            Dictionary(items.map { ($0.fingerprint, $0) }, uniquingKeysWith: { _, newest in newest }).values
        )
        let context = makeBackgroundContext()
        var upsertError: Error?
        context.performAndWait {
            do {
                var existingByFingerprint: [String: PinnedClip] = [:]
                let fingerprints = uniqueItems.map(\.fingerprint)
                for start in stride(from: 0, to: fingerprints.count, by: 200) {
                    let end = min(start + 200, fingerprints.count)
                    let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
                    request.predicate = NSPredicate(
                        format: "fingerprint IN %@",
                        Array(fingerprints[start..<end])
                    )
                    request.fetchBatchSize = 200
                    for clip in try context.fetch(request) {
                        if let fingerprint = clip.fingerprint {
                            existingByFingerprint[fingerprint] = clip
                        }
                    }
                }

                for item in uniqueItems {
                    let clip = existingByFingerprint[item.fingerprint] ?? PinnedClip(context: context)
                    Self.update(clip, from: item)
                }
                try save(context: context)
            } catch {
                upsertError = error
            }
        }
        if let upsertError {
            throw upsertError
        }
    }

    func remove(fingerprint: String) throws {
        try remove(fingerprints: [fingerprint])
    }

    func remove(fingerprints: [String]) throws {
        let uniqueFingerprints = Array(Set(fingerprints))
        guard !uniqueFingerprints.isEmpty else { return }
        let context = makeBackgroundContext()
        var removeError: Error?
        context.performAndWait {
            do {
                for start in stride(from: 0, to: uniqueFingerprints.count, by: 200) {
                    let end = min(start + 200, uniqueFingerprints.count)
                    let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
                    request.predicate = NSPredicate(
                        format: "fingerprint IN %@",
                        Array(uniqueFingerprints[start..<end])
                    )
                    request.fetchBatchSize = 200
                    try context.fetch(request).forEach(context.delete)
                }
                if context.hasChanges {
                    try save(context: context)
                }
            } catch {
                removeError = error
            }
        }
        if let removeError {
            throw removeError
        }
    }

    func removeAll() throws {
        try replaceAll(with: [])
    }

    /// Replace the cloud history in one transaction so resets cannot expose a partially written
    /// database or trigger one SQLite checkpoint per item.
    func replaceAll(with items: [ClipboardItem]) throws {
        let uniqueItems = Array(
            Dictionary(items.map { ($0.fingerprint, $0) }, uniquingKeysWith: { _, newest in newest }).values
        )
        let context = makeBackgroundContext()
        var removeError: Error?
        context.performAndWait {
            let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
            request.fetchBatchSize = 200
            do {
                let results = try context.fetch(request)
                results.forEach { context.delete($0) }
                for item in uniqueItems {
                    Self.update(PinnedClip(context: context), from: item)
                }
                try save(context: context)
            } catch {
                removeError = error
            }
        }
        if let removeError {
            throw removeError
        }
    }

    private static func update(_ clip: PinnedClip, from item: ClipboardItem) {
        clip.id = item.id
        clip.createdAt = item.createdAt
        clip.type = item.type.rawValue
        clip.textContent = item.textContent
        clip.rtfData = item.rtfData
        clip.imageData = item.imageData
        clip.urlString = item.urlString
        clip.fileBookmarkData = archiveFileBookmarks(item.fileURLs)
        clip.sourceAppBundleId = item.sourceAppBundleId
        clip.sourceAppName = item.sourceAppName
        clip.isPinned = item.isPinned
        clip.pinnedTitle = item.pinnedTitle
        clip.typesArchive = encodeTypesData(item.typesData)
        clip.fingerprint = item.fingerprint
    }

    private func makeBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }

    private func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            NSLog("PinnedStore save error: \(error)")
            throw error
        }
    }

    private static func encodeTypesData(_ types: [NSPasteboard.PasteboardType: Data]) -> Data? {
        let mapped = types.reduce(into: [String: Data]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        return try? PropertyListEncoder().encode(mapped)
    }

    private static func decodeTypesData(_ data: Data?) -> [NSPasteboard.PasteboardType: Data] {
        guard let data,
              let mapped = try? PropertyListDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return mapped.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, entry in
            result[NSPasteboard.PasteboardType(entry.key)] = entry.value
        }
    }

    private static func archiveFileBookmarks(_ urls: [URL]) -> Data? {
        let bookmarks = urls.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return try? PropertyListEncoder().encode(bookmarks)
    }

    private static func resolveFileBookmarks(_ data: Data) -> [URL] {
        guard let bookmarks = try? PropertyListDecoder().decode([Data].self, from: data) else { return [] }
        return bookmarks.compactMap { bookmark in
            var isStale = false
            return try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
    }
}
