import Combine
import Foundation
import SwiftUI

final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published private(set) var tags: [Tag] = []
    /// Maps item fingerprints to tag IDs
    @Published private(set) var itemTags: [String: Set<UUID>] = [:]

    private let persistence = TagPersistence()

    private init() {
        let loaded = persistence.load()
        tags = loaded.tags.sorted { $0.sortOrder < $1.sortOrder }
        itemTags = loaded.itemTags
    }

    // MARK: - Tag CRUD

    @discardableResult
    func create(name: String, color: String = "#007AFF") -> Tag {
        let maxOrder = tags.map { $0.sortOrder }.max() ?? -1
        let tag = Tag(
            name: name,
            color: color,
            sortOrder: maxOrder + 1
        )
        tags.append(tag)
        save()
        return tag
    }

    func update(_ tag: Tag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[index] = tag
        save()
    }

    func update(_ tagId: UUID, name: String, color: String) {
        guard let index = tags.firstIndex(where: { $0.id == tagId }) else { return }
        tags[index].name = name
        tags[index].color = color
        save()
    }

    func delete(_ tagId: UUID) {
        tags.removeAll { $0.id == tagId }
        // Remove tag from all items
        for key in itemTags.keys {
            itemTags[key]?.remove(tagId)
        }
        // Reorder remaining tags
        for i in 0..<tags.count {
            tags[i].sortOrder = i
        }
        save()
    }

    func delete(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        // Remove tag from all items
        for key in itemTags.keys {
            itemTags[key]?.remove(tag.id)
        }
        // Reorder remaining tags
        for i in 0..<tags.count {
            tags[i].sortOrder = i
        }
        save()
    }

    func reorder(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        for i in 0..<tags.count {
            tags[i].sortOrder = i
        }
        save()
    }

    // MARK: - Item-Tag Associations

    func addTag(_ tagId: UUID, to fingerprint: String) {
        if itemTags[fingerprint] == nil {
            itemTags[fingerprint] = []
        }
        itemTags[fingerprint]?.insert(tagId)
        save()
    }

    func removeTag(_ tagId: UUID, from fingerprint: String) {
        itemTags[fingerprint]?.remove(tagId)
        if itemTags[fingerprint]?.isEmpty == true {
            itemTags.removeValue(forKey: fingerprint)
        }
        save()
    }

    func toggleTag(_ tagId: UUID, for fingerprint: String) {
        if itemTags[fingerprint]?.contains(tagId) == true {
            removeTag(tagId, from: fingerprint)
        } else {
            addTag(tagId, to: fingerprint)
        }
    }

    func removeAllTags(from fingerprint: String) {
        itemTags.removeValue(forKey: fingerprint)
        save()
    }

    func tags(for fingerprint: String) -> [Tag] {
        guard let tagIds = itemTags[fingerprint] else { return [] }
        return tags.filter { tagIds.contains($0.id) }
    }

    func hasTag(_ tagId: UUID, fingerprint: String) -> Bool {
        itemTags[fingerprint]?.contains(tagId) == true
    }

    func itemsWithTag(_ tagId: UUID) -> Set<String> {
        Set(itemTags.filter { $0.value.contains(tagId) }.keys)
    }

    // MARK: - Persistence

    private func save() {
        persistence.save(tags: tags, itemTags: itemTags)
    }
}

// MARK: - Tag Persistence

private struct TagData: Codable {
    let tags: [Tag]
    let itemTags: [String: [UUID]] // Codable needs array, not Set

    init(tags: [Tag], itemTags: [String: Set<UUID>]) {
        self.tags = tags
        self.itemTags = itemTags.mapValues { Array($0) }
    }

    func toItemTags() -> [String: Set<UUID>] {
        itemTags.mapValues { Set($0) }
    }
}

private final class TagPersistence {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pastrDir = appSupport.appendingPathComponent("Pastr")
        try? FileManager.default.createDirectory(at: pastrDir, withIntermediateDirectories: true)
        fileURL = pastrDir.appendingPathComponent("tags.json")
    }

    func load() -> (tags: [Tag], itemTags: [String: Set<UUID>]) {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let tagData = try? JSONDecoder().decode(TagData.self, from: data) else {
            return ([], [:])
        }
        return (tagData.tags, tagData.toItemTags())
    }

    func save(tags: [Tag], itemTags: [String: Set<UUID>]) {
        DispatchQueue.global(qos: .utility).async { [fileURL] in
            let tagData = TagData(tags: tags, itemTags: itemTags)
            guard let data = try? JSONEncoder().encode(tagData) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
