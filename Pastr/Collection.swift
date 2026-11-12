import Foundation

struct Collection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol name
    var color: String // Hex color
    var itemFingerprints: [String] {  // Track items by fingerprint for deduplication
        didSet { fingerprintSet = Set(itemFingerprints) }
    }
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    /// O(1) membership cache mirroring `itemFingerprints`; never encoded.
    private var fingerprintSet: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, color, itemFingerprints, createdAt, updatedAt, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        let fingerprints = try container.decode([String].self, forKey: .itemFingerprints)
        itemFingerprints = fingerprints
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        fingerprintSet = Set(fingerprints)
    }

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
        self.fingerprintSet = Set(itemFingerprints)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    mutating func addItem(fingerprint: String) {
        if !fingerprintSet.contains(fingerprint) {
            itemFingerprints.append(fingerprint)
            updatedAt = Date()
        }
    }

    mutating func removeItem(fingerprint: String) {
        itemFingerprints.removeAll { $0 == fingerprint }
        updatedAt = Date()
    }

    func contains(fingerprint: String) -> Bool {
        fingerprintSet.contains(fingerprint)
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
