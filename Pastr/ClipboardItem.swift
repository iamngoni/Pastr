import AppKit

struct ClipboardItem: Identifiable, Hashable {
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
    let isPinned: Bool
    let pinnedTitle: String?
    let typesData: [NSPasteboard.PasteboardType: Data]
    let fingerprint: String

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

    var relativeTime: String {
        RelativeDateTimeFormatter.shared.localizedString(for: createdAt, relativeTo: Date())
    }

    var image: NSImage? {
        guard let imageData else { return nil }
        return NSImage(data: imageData)
    }

    var sourceAppIcon: NSImage? {
        guard let bundleId = sourceAppBundleId,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
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
        if let urlString {
            item.setString(urlString, forType: .URL)
        }

        pasteboard.writeObjects([item])
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
