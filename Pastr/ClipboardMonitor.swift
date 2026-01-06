import AppKit

final class ClipboardMonitor {
    private let historyStore: ClipboardHistoryStore
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: Timer?

    init(historyStore: ClipboardHistoryStore) {
        self.historyStore = historyStore
        changeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        capturePasteboardItem()
    }

    private func capturePasteboardItem() {
        guard let pasteboardItem = pasteboard.pasteboardItems?.first else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleId = frontmost?.bundleIdentifier
        let appName = frontmost?.localizedName

        if bundleId == Bundle.main.bundleIdentifier {
            return
        }

        let item = ClipboardMonitor.makeClipboardItem(
            from: pasteboardItem,
            pasteboard: pasteboard,
            sourceBundleId: bundleId,
            sourceName: appName
        )

        historyStore.add(item)
    }

    private static func makeClipboardItem(
        from item: NSPasteboardItem,
        pasteboard: NSPasteboard,
        sourceBundleId: String?,
        sourceName: String?
    ) -> ClipboardItem {
        let types = item.types
        var typesData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in types {
            if let data = item.data(forType: type) {
                typesData[type] = data
            } else if let string = item.string(forType: type) {
                typesData[type] = string.data(using: .utf8)
            }
        }

        let textContent = item.string(forType: .string)
        let rtfData = item.data(forType: .rtf)

        // Try multiple image formats - apps use different ones
        var imageData: Data?
        if let tiffData = item.data(forType: .tiff) {
            imageData = tiffData
        } else if let pngData = item.data(forType: .png) {
            imageData = pngData
        } else if let pdfData = item.data(forType: .pdf) {
            // Some apps copy images as PDF
            imageData = pdfData
        } else if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
                  let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
                  let image = images.first,
                  let tiffRep = image.tiffRepresentation {
            // Fallback: read as NSImage and convert to TIFF
            imageData = tiffRep
        }

        let urlString = item.string(forType: .URL)

        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []

        let type = ClipboardMonitor.resolveType(
            text: textContent,
            rtf: rtfData,
            imageData: imageData,
            urlString: urlString,
            fileURLs: fileURLs
        )

        let fingerprint = ClipboardMonitor.fingerprint(for: typesData, text: textContent, url: urlString, files: fileURLs)

        return ClipboardItem(
            id: UUID(),
            createdAt: Date(),
            type: type,
            textContent: textContent,
            rtfData: rtfData,
            imageData: imageData,
            urlString: urlString,
            fileURLs: fileURLs,
            sourceAppBundleId: sourceBundleId,
            sourceAppName: sourceName,
            isPinned: false,
            pinnedTitle: nil,
            typesData: typesData,
            fingerprint: fingerprint
        )
    }

    private static func resolveType(
        text: String?,
        rtf: Data?,
        imageData: Data?,
        urlString: String?,
        fileURLs: [URL]
    ) -> ClipboardItemType {
        if imageData != nil {
            return .image
        }
        if let urlString, !urlString.isEmpty {
            return .link
        }
        if !fileURLs.isEmpty {
            return .file
        }
        if rtf != nil {
            return .richText
        }
        if let text, !text.isEmpty {
            return .text
        }
        return .other
    }

    private static func fingerprint(
        for typesData: [NSPasteboard.PasteboardType: Data],
        text: String?,
        url: String?,
        files: [URL]
    ) -> String {
        var hasher = Hasher()
        hasher.combine(text)
        hasher.combine(url)
        hasher.combine(files.map { $0.absoluteString }.joined(separator: ","))
        for type in typesData.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            hasher.combine(type.rawValue)
            hasher.combine(typesData[type]?.count ?? 0)
        }
        return String(hasher.finalize())
    }
}
