import AppKit
import Foundation

struct ClipboardItem: Identifiable, nonisolated Hashable {
    static let cardPreviewCharacterLimit = 2_000
    static let detailPreviewCharacterLimit = 20_000

    let id: UUID
    let createdAt: Date
    let type: ClipboardItemType
    let textContent: String?
    let rtfData: Data?
    let imageData: Data?
    let urlString: String?
    let fileURLs: [URL]
    let sourceAppBundleId: String?
    let sourceAppName: String?
    var isPinned: Bool
    var pinnedTitle: String?
    let typesData: [NSPasteboard.PasteboardType: Data]
    let fingerprint: String

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.createdAt == rhs.createdAt &&
        lhs.type == rhs.type &&
        lhs.textContent?.count == rhs.textContent?.count &&
        lhs.rtfData?.count == rhs.rtfData?.count &&
        lhs.imageData?.count == rhs.imageData?.count &&
        lhs.urlString == rhs.urlString &&
        lhs.fileURLs == rhs.fileURLs &&
        lhs.sourceAppBundleId == rhs.sourceAppBundleId &&
        lhs.sourceAppName == rhs.sourceAppName &&
        lhs.isPinned == rhs.isPinned &&
        lhs.pinnedTitle == rhs.pinnedTitle &&
        lhs.typesData.count == rhs.typesData.count &&
        lhs.fingerprint == rhs.fingerprint
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(createdAt)
        hasher.combine(type)
        hasher.combine(textContent?.count)
        hasher.combine(rtfData?.count)
        hasher.combine(imageData?.count)
        hasher.combine(urlString)
        hasher.combine(fileURLs)
        hasher.combine(sourceAppBundleId)
        hasher.combine(sourceAppName)
        hasher.combine(isPinned)
        hasher.combine(pinnedTitle)
        hasher.combine(typesData.count)
        hasher.combine(fingerprint)
    }

    var previewText: String {
        if let pinnedTitle, !pinnedTitle.isEmpty {
            return pinnedTitle
        }
        if let textContent, !textContent.isEmpty {
            return textContent
        }
        if let urlString, !urlString.isEmpty {
            return urlString
        }
        if !fileURLs.isEmpty {
            return fileURLs.map { $0.lastPathComponent }.joined(separator: ", ")
        }
        return type.label
    }

    /// A bounded display-only value for cards. The original payload remains available through
    /// `textContent`, `plainText`, and `write(to:)` so preview safety never truncates a copy.
    var cardPreviewText: String {
        Self.boundedPreview(previewText, limit: Self.cardPreviewCharacterLimit)
    }

    /// A larger, still bounded display-only value for the quick-preview panel.
    var detailPreviewText: String {
        Self.boundedPreview(previewText, limit: Self.detailPreviewCharacterLimit)
    }

    var plainText: String? {
        if let textContent, !textContent.isEmpty {
            return textContent
        }
        if let urlString, !urlString.isEmpty {
            return urlString
        }
        if !fileURLs.isEmpty {
            return fileURLs.map { $0.path }.joined(separator: " ")
        }
        return nil
    }

    var relativeTime: String {
        RelativeDateTimeFormatter.shared.localizedString(for: createdAt, relativeTo: Date())
    }

    var attributedPreview: AttributedString? {
        guard let rtfData else { return nil }
        return AttributedStringCache.shared.attributedString(for: fingerprint, rtfData: rtfData)
    }

    var image: NSImage? {
        guard let imageData else { return nil }
        return ClipboardImageCache.shared.image(for: fingerprint, data: imageData)
    }

    var sourceAppIcon: NSImage? {
        guard let bundleId = sourceAppBundleId else { return nil }
        return AppIconCache.shared.cachedIcon(for: bundleId)
    }

    func loadSourceAppIconAsync(completion: @escaping (NSImage?) -> Void) {
        guard let bundleId = sourceAppBundleId else {
            completion(nil)
            return
        }
        AppIconCache.shared.icon(for: bundleId, completion: completion)
    }

    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in typesData {
            item.setData(data, forType: type)
        }

        if let textContent {
            item.setString(textContent, forType: .string)
        }
        if let rtfData {
            item.setData(rtfData, forType: .rtf)
        }
        if let urlString {
            item.setString(urlString, forType: .URL)
        }

        var objects: [NSPasteboardWriting] = [item]
        if let imageData, let image = ClipboardImageCache.shared.image(for: fingerprint, data: imageData) {
            objects.append(image)
        }
        if !fileURLs.isEmpty {
            objects.append(contentsOf: fileURLs.map { $0 as NSURL })
        }
        pasteboard.writeObjects(objects)
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()

        if let textContent {
            provider.registerObject(textContent as NSString, visibility: .all)
        }

        if let urlString, let url = URL(string: urlString) {
            provider.registerObject(url as NSURL, visibility: .all)
        }

        if let image {
            provider.registerObject(image, visibility: .all)
        }

        if let fileURL = fileURLs.first {
            provider.registerObject(fileURL as NSURL, visibility: .all)
        }

        for (type, data) in typesData {
            provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }

        return provider
    }

    private static func boundedPreview(_ text: String, limit: Int) -> String {
        guard let end = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex),
              end != text.endIndex else { return text }
        return String(text[..<end]) + "\n…"
    }
}

final class ClipboardImageCache {
    static let shared = ClipboardImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for fingerprint: String, data: Data) -> NSImage? {
        let key = fingerprint as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func removeImage(for fingerprint: String) {
        cache.removeObject(forKey: fingerprint as NSString)
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}

enum ClipboardItemType: String, CaseIterable {
    case text
    case image
    case link
    case file
    case richText
    case other

    var label: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .link: return "Link"
        case .file: return "File"
        case .richText: return "Rich Text"
        case .other: return "Other"
        }
    }
}

extension RelativeDateTimeFormatter {
    static let shared: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
