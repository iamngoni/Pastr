import AppKit
import CoreData

final class PinnedStore {
    static let shared = PinnedStore()

    private let container: NSPersistentCloudKitContainer

    private init() {
        container = NSPersistentCloudKitContainer(name: "Pastr")
        let description = container.persistentStoreDescriptions.first
        description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.za.co.codecraftsolutions.Pastr")
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error {
                NSLog("PinnedStore load error: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func fetchPinned() -> [ClipboardItem] {
        let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let results = try? container.viewContext.fetch(request) else {
            return []
        }
        return results.compactMap { clip in
            guard let id = clip.id,
                  let createdAt = clip.createdAt,
                  let type = clip.type,
                  let fingerprint = clip.fingerprint else {
                return nil
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
                isPinned: true,
                pinnedTitle: clip.pinnedTitle,
                typesData: Self.decodeTypesData(clip.typesArchive),
                fingerprint: fingerprint
            )
        }
    }

    func savePinned(_ item: ClipboardItem) {
        let context = container.viewContext
        let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
        request.predicate = NSPredicate(format: "fingerprint == %@", item.fingerprint)
        let existing = (try? context.fetch(request))?.first
        let clip = existing ?? PinnedClip(context: context)

        clip.id = item.id
        clip.createdAt = item.createdAt
        clip.type = item.type.rawValue
        clip.textContent = item.textContent
        clip.rtfData = item.rtfData
        clip.imageData = item.imageData
        clip.urlString = item.urlString
        clip.fileBookmarkData = Self.archiveFileBookmarks(item.fileURLs)
        clip.sourceAppBundleId = item.sourceAppBundleId
        clip.sourceAppName = item.sourceAppName
        clip.pinnedTitle = item.pinnedTitle
        clip.typesArchive = Self.encodeTypesData(item.typesData)
        clip.fingerprint = item.fingerprint

        save(context: context)
    }

    func removePinned(fingerprint: String) {
        let context = container.viewContext
        let request = NSFetchRequest<PinnedClip>(entityName: "PinnedClip")
        request.predicate = NSPredicate(format: "fingerprint == %@", fingerprint)
        if let clip = try? context.fetch(request).first {
            context.delete(clip)
            save(context: context)
        }
    }

    private func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            NSLog("PinnedStore save error: \(error)")
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
