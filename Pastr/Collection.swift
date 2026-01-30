import Foundation

struct Collection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol name
    var color: String // Hex color
    var itemFingerprints: [String]  // Track items by fingerprint for deduplication
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        color: String = "#007AFF",
        itemFingerprints: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.itemFingerprints = itemFingerprints
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    mutating func addItem(fingerprint: String) {
        if !itemFingerprints.contains(fingerprint) {
            itemFingerprints.append(fingerprint)
            updatedAt = Date()
        }
    }

    mutating func removeItem(fingerprint: String) {
        itemFingerprints.removeAll { $0 == fingerprint }
        updatedAt = Date()
    }

    func contains(fingerprint: String) -> Bool {
        itemFingerprints.contains(fingerprint)
    }
}

// Predefined collection colors
extension Collection {
    static let availableColors: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Pink", "#FF2D55"),
        ("Red", "#FF3B30"),
        ("Orange", "#FF9500"),
        ("Yellow", "#FFCC00"),
        ("Green", "#34C759"),
        ("Teal", "#5AC8FA"),
        ("Gray", "#8E8E93")
    ]

    static let availableIcons: [String] = [
        "folder.fill",
        "star.fill",
        "heart.fill",
        "bookmark.fill",
        "tag.fill",
        "flag.fill",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "briefcase.fill",
        "house.fill",
        "person.fill",
        "globe",
        "doc.fill",
        "photo.fill"
    ]
}
