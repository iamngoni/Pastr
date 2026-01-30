import Foundation

struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String // Hex color
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        color: String = "#007AFF",
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
