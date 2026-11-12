import AppKit
import Foundation
import ImageIO

struct ClipboardItem: Identifiable, nonisolated Hashable {
    static let cardPreviewCharacterLimit = 800
    static let detailPreviewCharacterLimit = 8_000

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
        lhs.urlString == rhs.urlString &&
        lhs.fileURLs == rhs.fileURLs &&
        lhs.sourceAppBundleId == rhs.sourceAppBundleId &&
        lhs.sourceAppName == rhs.sourceAppName &&
        lhs.isPinned == rhs.isPinned &&
        lhs.pinnedTitle == rhs.pinnedTitle &&
        lhs.fingerprint == rhs.fingerprint
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(createdAt)
        hasher.combine(type)
        hasher.combine(urlString)
        hasher.combine(fileURLs)
        hasher.combine(sourceAppBundleId)
        hasher.combine(sourceAppName)
        hasher.combine(isPinned)
        hasher.combine(pinnedTitle)
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
        // Returns the cached icon, or nil while an async load is kicked off. Views that observe
        // `AppIconCache.shared` re-render when the load completes.
        return AppIconCache.shared.icon(forBundleID: bundleId)
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
        if let imageData {
            if Self.hasPNGSignature(imageData) || Self.hasPDFSignature(imageData) {
                item.setData(imageData, forType: Self.hasPNGSignature(imageData) ? .png : .pdf)
                // Many apps (Slack, browsers, older AppKit apps) only read bitmaps/TIFF. Offer
                // TIFF lazily so it's only rendered if the receiving app asks for it.
                if typesData[.tiff] == nil {
                    let provider = LazyTIFFProvider(imageData: imageData)
                    Self.activeTIFFProvider = provider
                    item.setDataProvider(provider, forTypes: [.tiff])
                }
            } else if let image = ClipboardImageCache.shared.image(for: fingerprint, data: imageData) {
                objects.append(image)
            }
        }
        if !fileURLs.isEmpty {
            objects.append(contentsOf: fileURLs.map { $0 as NSURL })
        }
        pasteboard.writeObjects(objects)
    }

    /// Keeps the current pasteboard's lazy TIFF provider alive until the next write.
    private static var activeTIFFProvider: LazyTIFFProvider?

    private static func hasPNGSignature(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }

    private static func hasPDFSignature(_ data: Data) -> Bool {
        data.starts(with: [0x25, 0x50, 0x44, 0x46])
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

    /// Longest-edge pixel budget for card thumbnails (enough for 2x retina cards).
    nonisolated static let cardMaxPixelSize = 600
    /// Pass as `maxPixelSize` to decode at full resolution.
    nonisolated static let fullSize = 0

    private let cache = NSCache<NSString, NSImage>()
    private let decodeQueue = DispatchQueue(label: "pastr.image-preview-decode", qos: .userInitiated)
    private let stateLock = NSLock()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private var variantsByFingerprint: [String: Set<Int>] = [:]

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    private func cacheKey(_ fingerprint: String, _ maxPixelSize: Int) -> String {
        "\(fingerprint)@\(maxPixelSize)"
    }

    /// Synchronous full-size image (used for drag/drop and pasteboard fallbacks).
    func image(for fingerprint: String, data: Data) -> NSImage? {
        let key = cacheKey(fingerprint, Self.fullSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        guard let image = NSImage(data: data) else { return nil }
        store(image, fingerprint: fingerprint, maxPixelSize: Self.fullSize, cost: data.count)
        return image
    }

    /// Cached decoded image (thumbnail by default) if already available.
    func cachedImage(for fingerprint: String, maxPixelSize: Int = ClipboardImageCache.cardMaxPixelSize) -> NSImage? {
        cache.object(forKey: cacheKey(fingerprint, maxPixelSize) as NSString)
    }

    /// Decode off the main thread and call `completion` on the main thread. By default the
    /// result is a downsampled thumbnail (longest edge <= `cardMaxPixelSize`). Concurrent
    /// requests for the same fingerprint/size share one decode.
    func loadImage(
        for fingerprint: String,
        data: Data,
        maxPixelSize: Int = ClipboardImageCache.cardMaxPixelSize,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = cacheKey(fingerprint, maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        stateLock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            stateLock.unlock()
            return
        }
        inFlight[key] = [completion]
        stateLock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let image = Self.decodedImage(from: data, maxPixelSize: maxPixelSize)
            if let image {
                self.store(image, fingerprint: fingerprint, maxPixelSize: maxPixelSize, cost: Self.bitmapCost(of: image))
            }
            self.stateLock.lock()
            let completions = self.inFlight.removeValue(forKey: key) ?? []
            self.stateLock.unlock()
            DispatchQueue.main.async {
                completions.forEach { $0(image) }
            }
        }
    }

    func removeImage(for fingerprint: String) {
        stateLock.lock()
        let sizes = variantsByFingerprint.removeValue(forKey: fingerprint) ?? []
        stateLock.unlock()
        for size in sizes {
            cache.removeObject(forKey: cacheKey(fingerprint, size) as NSString)
        }
    }

    func clearCache() {
        cache.removeAllObjects()
        stateLock.lock()
        variantsByFingerprint.removeAll()
        stateLock.unlock()
    }

    private func store(_ image: NSImage, fingerprint: String, maxPixelSize: Int, cost: Int) {
        cache.setObject(image, forKey: cacheKey(fingerprint, maxPixelSize) as NSString, cost: cost)
        stateLock.lock()
        variantsByFingerprint[fingerprint, default: []].insert(maxPixelSize)
        stateLock.unlock()
    }

    /// Decoded bitmap footprint: width * height * 4 bytes.
    private nonisolated static func bitmapCost(of image: NSImage) -> Int {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return rep.pixelsWide * rep.pixelsHigh * 4
        }
        return Int(image.size.width * image.size.height * 4)
    }

    private nonisolated static func decodedImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }

        // Don't upscale: images already within budget take the plain decode path.
        var needsThumbnail = maxPixelSize > 0
        if needsThumbnail,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) <= maxPixelSize {
            needsThumbnail = false
        }

        var cgImage: CGImage?
        if needsThumbnail {
            cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ] as CFDictionary
            )
        }
        if cgImage == nil {
            cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            )
        }
        guard let cgImage else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
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


/// Renders TIFF from stored PNG/PDF data only when a pasting app requests it.
private final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider {
    private let imageData: Data

    init(imageData: Data) {
        self.imageData = imageData
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff,
              let image = NSImage(data: imageData),
              let tiff = image.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
