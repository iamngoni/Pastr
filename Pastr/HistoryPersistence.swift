import AppKit
import Foundation

final class HistoryPersistence {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "pastr.history.persistence")

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Pastr", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        fileURL = folder.appendingPathComponent("history.json")
    }

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decodeItems(from: data)) ?? []
    }

    func save(_ items: [ClipboardItem]) {
        queue.async {
            guard let data = try? self.encodeItems(items) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }

    func encodeItems(_ items: [ClipboardItem]) throws -> Data {
        let records = items.map { ClipboardItemRecord(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    func decodeItems(from data: Data) throws -> [ClipboardItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([ClipboardItemRecord].self, from: data)
        return records.map { $0.toClipboardItem() }
    }
}

private struct ClipboardItemRecord: Codable {
    let id: UUID
    let createdAt: Date
    let type: String
    let textContent: String?
    let rtfData: Data?
    let imageData: Data?
    let urlString: String?
    let fileURLs: [URL]
    let sourceAppBundleId: String?
    let sourceAppName: String?
    let isPinned: Bool
    let pinnedTitle: String?
    let typesData: [String: Data]
    let fingerprint: String

    init(from item: ClipboardItem) {
        id = item.id
        createdAt = item.createdAt
        type = item.type.rawValue
        textContent = item.textContent
        rtfData = item.rtfData
        imageData = item.imageData
        urlString = item.urlString
        fileURLs = item.fileURLs
        sourceAppBundleId = item.sourceAppBundleId
        sourceAppName = item.sourceAppName
        isPinned = item.isPinned
        pinnedTitle = item.pinnedTitle
        var types: [String: Data] = [:]
        item.typesData.forEach { key, value in
            types[key.rawValue] = value
        }
        typesData = types
        fingerprint = item.fingerprint
    }

    func toClipboardItem() -> ClipboardItem {
        let typeValue = ClipboardItemType(rawValue: type) ?? .other
        let pasteboardTypes = typesData.reduce(into: [NSPasteboard.PasteboardType: Data]()) { partialResult, entry in
            partialResult[NSPasteboard.PasteboardType(entry.key)] = entry.value
        }
        return ClipboardItem(
            id: id,
            createdAt: createdAt,
            type: typeValue,
            textContent: textContent,
            rtfData: rtfData,
            imageData: imageData,
            urlString: urlString,
            fileURLs: fileURLs,
            sourceAppBundleId: sourceAppBundleId,
            sourceAppName: sourceAppName,
            isPinned: isPinned,
            pinnedTitle: pinnedTitle,
            typesData: pasteboardTypes,
            fingerprint: fingerprint
        )
    }
}
