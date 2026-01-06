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
extension PinnedClip {
    @nonobjc
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "PinnedClip", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.type = ""
        self.fingerprint = UUID().uuidString
    }
}

