import AppKit
import Foundation

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
    var isPinned: Bool
    var pinnedTitle: String?
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
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        guard let nsAttributed = try? NSAttributedString(data: rtfData, options: options, documentAttributes: nil) else {
            return nil
        }
        return AttributedString(nsAttributed)
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

        var objects: [NSPasteboardWriting] = [item]
        if !fileURLs.isEmpty {
            objects.append(contentsOf: fileURLs.map { $0 as NSURL })
        }
        pasteboard.writeObjects(objects)
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
