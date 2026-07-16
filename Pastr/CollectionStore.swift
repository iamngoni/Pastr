import Combine
import Foundation
import SwiftUI

final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    @Published private(set) var collections: [Collection] = []

    private let persistence = CollectionPersistence()
    private let defaults = UserDefaults.standard
    private let migrationKey = "collectionMigrationFromPinnedCompleted"

    private init() {
        collections = persistence.load()
        // Collections sorted by sortOrder
        collections.sort { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - CRUD Operations

    func create(name: String, icon: String = "folder.fill", color: String = "#007AFF") -> Collection {
        let maxOrder = collections.map { $0.sortOrder }.max() ?? -1
        let collection = Collection(
            name: name,
            icon: icon,
            color: color,
            sortOrder: maxOrder + 1
        )
        collections.append(collection)
        save()
        return collection
    }

    func update(_ collection: Collection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index] = collection
        save()
    }

    func delete(_ collection: Collection) {
        collections.removeAll { $0.id == collection.id }
        // Reorder remaining collections
        for i in 0..<collections.count {
            collections[i].sortOrder = i
        }
        save()
    }

    func reorder(from source: IndexSet, to destination: Int) {
        collections.move(fromOffsets: source, toOffset: destination)
        for i in 0..<collections.count {
            collections[i].sortOrder = i
        }
        save()
    }

    // MARK: - Item Management

    func addItem(fingerprint: String, to collectionId: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        collections[index].addItem(fingerprint: fingerprint)
        save()
    }

    func removeItem(fingerprint: String, from collectionId: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        collections[index].removeItem(fingerprint: fingerprint)
        save()
    }

    func removeItemFromAll(fingerprint: String) {
        for i in 0..<collections.count {
            collections[i].removeItem(fingerprint: fingerprint)
        }
        save()
    }

    func collections(containing fingerprint: String) -> [Collection] {
        collections.filter { $0.contains(fingerprint: fingerprint) }
    }

    func isItemInAnyCollection(fingerprint: String) -> Bool {
        collections.contains { $0.contains(fingerprint: fingerprint) }
    }

    // MARK: - Migration

    /// Migrate from old isPinned system to collections
    /// Returns true if migration was performed
    @discardableResult
    func migrateFromPinnedIfNeeded(pinnedFingerprints: [String]) -> Bool {
        guard !defaults.bool(forKey: migrationKey) else { return false }
        guard !pinnedFingerprints.isEmpty else {
            defaults.set(true, forKey: migrationKey)
            return false
        }

        // Create default "Pinned" collection if it doesn't exist
        if !collections.contains(where: { $0.name == "Pinned" }) {
            var pinnedCollection = Collection(
                name: "Pinned",
                icon: "pin.fill",
                color: "#FF9500",
                sortOrder: 0
            )
            pinnedCollection.itemFingerprints = pinnedFingerprints
            collections.insert(pinnedCollection, at: 0)

            // Reorder other collections
            for i in 1..<collections.count {
                collections[i].sortOrder = i
            }
            save()
        }

        defaults.set(true, forKey: migrationKey)
        return true
    }

    // MARK: - File Addition

    /// Create a ClipboardItem from file URLs and add to a collection
    /// Returns the created item so it can be added to history
    func addFiles(_ urls: [URL], to collectionId: UUID, historyStore: ClipboardHistoryStore) -> ClipboardItem? {
        guard !urls.isEmpty else { return nil }

        // Create a ClipboardItem from the files
        let item = ClipboardItem(
            id: UUID(),
            createdAt: Date(),
            type: .file,
            textContent: nil,
            rtfData: nil,
            imageData: nil,
            urlString: nil,
            fileURLs: urls,
            sourceAppBundleId: Bundle.main.bundleIdentifier,
            sourceAppName: "Pastr",
            isPinned: false,
            pinnedTitle: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files",
            typesData: [:],
            fingerprint: urls.map { $0.absoluteString }.joined(separator: ",").hashValue.description
        )

        // Add to history
        historyStore.add(item)

        // Add to collection
        addItem(fingerprint: item.fingerprint, to: collectionId)

        return item
    }

    // MARK: - Persistence

    private func save() {
        persistence.save(collections)
    }
}

// MARK: - Collection Persistence

private final class CollectionPersistence {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "pastr.collections.persistence", qos: .utility)

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pastrDir = appSupport.appendingPathComponent("Pastr")
        try? FileManager.default.createDirectory(at: pastrDir, withIntermediateDirectories: true)
        fileURL = pastrDir.appendingPathComponent("collections.json")
    }

    func load() -> [Collection] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let collections = try? JSONDecoder().decode([Collection].self, from: data) else {
            return []
        }
        return collections
    }

    func save(_ collections: [Collection]) {
        queue.async { [fileURL] in
            guard let data = try? JSONEncoder().encode(collections) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
