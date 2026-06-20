import CoreData
import Foundation

final class PastrCloudClipStore {
    static let shared = PastrCloudClipStore()

    let container: NSPersistentCloudKitContainer
    private let loadError: Error?

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: PastrSharedConstants.coreDataModelName)

        let description = container.persistentStoreDescriptions.first
        if inMemory {
            description?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL = Self.persistentStoreURL {
            description?.url = storeURL
        }
        if Self.hasCloudKitEntitlement {
            description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: PastrSharedConstants.cloudKitContainerIdentifier
            )
        }
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        var storeLoadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            storeLoadError = error
            semaphore.signal()
        }
        semaphore.wait()

        loadError = storeLoadError
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func fetchAll(limit: Int? = nil) throws -> [PastrClip] {
        if let loadError {
            throw loadError
        }

        var result: Result<[PastrClip], Error> = .success([])
        container.viewContext.performAndWait {
            let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            if let limit {
                request.fetchLimit = limit
            }

            do {
                let clips = try container.viewContext.fetch(request)
                result = .success(clips.compactMap(Self.makeClip(from:)).filter { !$0.isTransientFileProviderLink })
            } catch {
                result = .failure(error)
            }
        }

        return try result.get()
    }

    func upsert(_ clip: PastrClip) throws {
        if let loadError {
            throw loadError
        }

        var result: Result<Void, Error> = .success(())
        container.viewContext.performAndWait {
            let context = container.viewContext
            let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
            request.predicate = NSPredicate(format: "fingerprint == %@", clip.fingerprint)
            request.fetchLimit = 1

            do {
                let managed = try context.fetch(request).first ?? PinnedClip(context: context)
                managed.id = clip.id
                managed.createdAt = clip.createdAt
                managed.type = clip.type.rawValue
                managed.textContent = clip.textContent
                managed.rtfData = clip.rtfData
                managed.imageData = clip.imageData
                managed.urlString = clip.urlString
                managed.fileBookmarkData = nil
                managed.sourceAppBundleId = clip.sourceAppBundleId
                managed.sourceAppName = clip.sourceAppName
                managed.isPinned = clip.isPinned
                managed.pinnedTitle = clip.pinnedTitle
                managed.typesArchive = Self.encodeRepresentations(clip.pasteboardRepresentations)
                managed.fingerprint = clip.fingerprint

                if context.hasChanges {
                    try context.save()
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }

        try result.get()
    }

    func remove(fingerprint: String) throws {
        if let loadError {
            throw loadError
        }

        var result: Result<Void, Error> = .success(())
        container.viewContext.performAndWait {
            let context = container.viewContext
            let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
            request.predicate = NSPredicate(format: "fingerprint == %@", fingerprint)
            request.fetchLimit = 1

            do {
                if let managed = try context.fetch(request).first {
                    context.delete(managed)
                    try context.save()
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }

        try result.get()
    }

    @discardableResult
    func refreshSharedCache(limit: Int = 80) throws -> [PastrClip] {
        let clips = try fetchAll(limit: limit)
        try PastrSharedClipCache.save(clips, limit: limit)
        return clips
    }

    private static var persistentStoreURL: URL? {
        let baseURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PastrSharedConstants.appGroupIdentifier
        ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        guard let folder = baseURL?.appendingPathComponent("PastrCloudStore", isDirectory: true) else {
            return nil
        }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Pastr.sqlite")
    }

    private static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["PASTR_ENABLE_SIMULATOR_CLOUDKIT"] == "1"
        #else
        true
        #endif
    }

    private static func makeClip(from managed: PinnedClip) -> PastrClip? {
        guard let id = managed.id,
              let createdAt = managed.createdAt,
              let rawType = managed.type,
              let fingerprint = managed.fingerprint else {
            return nil
        }

        let type = PastrClipType(rawValue: rawType) ?? .other
        let title = PastrClipText.title(
            for: type,
            text: managed.textContent,
            url: managed.urlString,
            fallback: managed.pinnedTitle
        )
        let detail = PastrClipText.detail(
            for: type,
            text: managed.textContent,
            url: managed.urlString
        )
        let source = managed.sourceAppName ?? "iCloud"

        return PastrClip(
            id: id,
            createdAt: createdAt,
            type: type,
            source: source,
            title: title,
            detail: detail,
            isPinned: managed.isPinned,
            textContent: managed.textContent,
            rtfData: managed.rtfData,
            imageData: managed.imageData,
            urlString: managed.urlString,
            sourceAppBundleId: managed.sourceAppBundleId,
            sourceAppName: managed.sourceAppName,
            pinnedTitle: managed.pinnedTitle,
            fingerprint: fingerprint,
            pasteboardRepresentations: decodeRepresentations(managed.typesArchive)
        )
    }

    private static func encodeRepresentations(_ representations: [String: Data]) -> Data? {
        guard !representations.isEmpty else { return nil }
        return try? PropertyListEncoder().encode(representations)
    }

    private static func decodeRepresentations(_ data: Data?) -> [String: Data] {
        guard let data,
              let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
