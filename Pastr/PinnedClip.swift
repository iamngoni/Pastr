import CoreData

@objc(PinnedClip)
final class PinnedClip: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var type: String
    @NSManaged var textContent: String?
    @NSManaged var rtfData: Data?
    @NSManaged var imageData: Data?
    @NSManaged var urlString: String?
    @NSManaged var fileBookmarkData: Data?
    @NSManaged var sourceAppBundleId: String?
    @NSManaged var sourceAppName: String?
    @NSManaged var pinnedTitle: String?
    @NSManaged var typesArchive: Data?
    @NSManaged var fingerprint: String
}
