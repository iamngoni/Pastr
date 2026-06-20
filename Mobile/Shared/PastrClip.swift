import CryptoKit
import Foundation

enum PastrClipType: String, CaseIterable, Codable, Identifiable {
    case text
    case link
    case image
    case richText
    case file
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .richText: "Rich Text"
        case .file: "File"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .richText: "doc.richtext"
        case .file: "doc"
        case .other: "square.stack.3d.up"
        }
    }
}

struct PastrClip: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let type: PastrClipType
    let source: String
    let title: String
    let detail: String
    let isPinned: Bool
    let tintName: PastrTintName
    let textContent: String?
    let rtfData: Data?
    let imageData: Data?
    let urlString: String?
    let sourceAppBundleId: String?
    let sourceAppName: String?
    let pinnedTitle: String?
    let fingerprint: String
    let pasteboardRepresentations: [String: Data]
    let thumbnailName: String?

    var relativeTime: String {
        PastrRelativeDateTimeFormatter.shared.localizedString(for: createdAt, relativeTo: Date())
    }

    var insertText: String {
        if type == .image {
            return ""
        }
        if let textContent, !textContent.isEmpty {
            return textContent
        }
        if let urlString, !urlString.isEmpty {
            return urlString
        }
        return title
    }

    var isTransientFileProviderLink: Bool {
        guard type == .link else {
            return false
        }

        let candidates = [urlString, textContent, detail].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        return candidates.contains { value in
            URL(string: value)?.isFileURL == true
        }
    }

    var hasWebURL: Bool {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        type: PastrClipType,
        source: String,
        title: String,
        detail: String,
        isPinned: Bool = false,
        tintName: PastrTintName? = nil,
        textContent: String? = nil,
        rtfData: Data? = nil,
        imageData: Data? = nil,
        urlString: String? = nil,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        pinnedTitle: String? = nil,
        fingerprint: String? = nil,
        pasteboardRepresentations: [String: Data] = [:],
        thumbnailName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.source = source
        self.title = title
        self.detail = detail
        self.isPinned = isPinned
        self.tintName = tintName ?? PastrTintName.preferred(for: type)
        self.textContent = textContent
        self.rtfData = rtfData
        self.imageData = imageData
        self.urlString = urlString
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.pinnedTitle = pinnedTitle
        self.fingerprint = fingerprint ?? PastrClipFingerprint.make(
            type: type,
            text: textContent,
            url: urlString,
            imageData: imageData,
            title: title
        )
        self.pasteboardRepresentations = pasteboardRepresentations
        self.thumbnailName = thumbnailName
    }
}

enum PastrTintName: String, Codable, Hashable {
    case blue
    case mint
    case violet
    case amber
    case graphite

    static func preferred(for type: PastrClipType) -> PastrTintName {
        switch type {
        case .text:
            return .blue
        case .link:
            return .mint
        case .image:
            return .violet
        case .richText:
            return .amber
        case .file, .other:
            return .graphite
        }
    }
}

enum PastrSampleClips {
    static let clips: [PastrClip] = [
        PastrClip(
            createdAt: Date().addingTimeInterval(-120),
            type: .link,
            source: "Maps",
            title: "Blue Bottle Coffee",
            detail: "bluebottlecoffee.com/cafes/embarcadero",
            isPinned: true,
            tintName: .mint,
            urlString: "https://bluebottlecoffee.com/cafes/embarcadero",
            thumbnailName: "map"
        ),
        PastrClip(
            createdAt: Date().addingTimeInterval(-180),
            type: .text,
            source: "Messages",
            title: "399 The Embarcadero",
            detail: "399 The Embarcadero, San Francisco, CA 94105",
            isPinned: true,
            tintName: .blue,
            textContent: "399 The Embarcadero, San Francisco, CA 94105"
        ),
        PastrClip(
            createdAt: Date().addingTimeInterval(-300),
            type: .image,
            source: "Photos",
            title: "Bay Bridge",
            detail: "Image copied from Photos",
            isPinned: false,
            tintName: .violet,
            thumbnailName: "bridge"
        ),
        PastrClip(
            createdAt: Date().addingTimeInterval(-540),
            type: .richText,
            source: "Notes",
            title: "Launch Notes - Q3",
            detail: "New dashboard widgets\nImproved search filters\nKeyboard enhancements",
            isPinned: true,
            tintName: .amber,
            textContent: "Launch Notes - Q3\n- New dashboard widgets\n- Improved search filters\n- Keyboard enhancements"
        ),
        PastrClip(
            createdAt: Date().addingTimeInterval(-720),
            type: .file,
            source: "Files",
            title: "Product Specs.pdf",
            detail: "1.4 MB - PDF",
            isPinned: false,
            tintName: .graphite
        )
    ]
}

enum PastrSharedConstants {
    static let appGroupIdentifier = "group.za.co.codecraftsolutions.Pastr"
    static let cloudKitContainerIdentifier = "iCloud.za.co.codecraftsolutions.Pastr"
    static let coreDataModelName = "Pastr"
    static let sharedCacheFilename = "clips-cache.json"
}

enum PastrClipFingerprint {
    static func make(
        type: PastrClipType,
        text: String?,
        url: String?,
        imageData: Data?,
        title: String
    ) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(type.rawValue.utf8))
        hasher.update(data: Data((text ?? "").utf8))
        hasher.update(data: Data((url ?? "").utf8))
        hasher.update(data: Data(title.utf8))
        if let imageData {
            hasher.update(data: imageData)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum PastrClipText {
    static func title(for type: PastrClipType, text: String?, url: String?, fallback: String? = nil) -> String {
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        switch type {
        case .link:
            return url.flatMap(URL.init(string:))?.host(percentEncoded: false) ?? url ?? "Link"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .richText:
            return firstLine(from: text) ?? "Rich Text"
        case .text:
            return firstLine(from: text) ?? "Text"
        case .other:
            return firstLine(from: text) ?? "Clip"
        }
    }

    static func detail(for type: PastrClipType, text: String?, url: String?, fallback: String? = nil) -> String {
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        switch type {
        case .link:
            return url ?? "URL"
        case .image:
            return "Image clip"
        case .file:
            return "File clip"
        case .richText, .text, .other:
            return text ?? type.label
        }
    }

    private static func firstLine(from text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.split(separator: "\n", maxSplits: 1).first ?? Substring(trimmed))
    }
}

private enum PastrRelativeDateTimeFormatter {
    static let shared: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
