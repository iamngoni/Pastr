import Foundation

enum PastrSharedClipCache {
    private static let maxCacheFileBytes = 24 * 1024 * 1024
    private static let maxClipImageBytes = 8 * 1024 * 1024
    private static let maxTotalImageBytes = 12 * 1024 * 1024

    static func load(limit: Int? = nil) -> [PastrClip] {
        guard let url = cacheURL,
              cacheFileIsReadable(url),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let clips = try? decoder.decode([PastrClip].self, from: data) else {
            return []
        }

        let visibleClips = clips.filter { !$0.isTransientFileProviderLink }

        if let limit {
            return Array(visibleClips.prefix(limit))
        }
        return visibleClips
    }

    static func save(_ clips: [PastrClip], limit: Int = 80) throws {
        guard let url = cacheURL else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let visibleClips = Array(clips.filter { !$0.isTransientFileProviderLink }.prefix(limit))
        var data = try encoder.encode(clipsForSharedCache(visibleClips))
        if data.count > maxCacheFileBytes {
            data = try encoder.encode(visibleClips.map { $0.sharedCacheCopy(imageData: nil) })
        }
        try data.write(to: url, options: .atomic)
    }

    static var cacheURL: URL? {
        let folder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PastrSharedConstants.appGroupIdentifier
        ) ?? fallbackFolder

        return folder?.appendingPathComponent(PastrSharedConstants.sharedCacheFilename)
    }

    private static var fallbackFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Pastr", isDirectory: true)
    }

    private static func cacheFileIsReadable(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }
        return size <= maxCacheFileBytes
    }

    private static func clipsForSharedCache(_ clips: [PastrClip]) -> [PastrClip] {
        var totalImageBytes = 0
        return clips.map { clip in
            var cachedImageData: Data?
            if let imageData = clip.imageData,
               imageData.count <= maxClipImageBytes,
               totalImageBytes + imageData.count <= maxTotalImageBytes {
                cachedImageData = imageData
                totalImageBytes += imageData.count
            }
            return clip.sharedCacheCopy(imageData: cachedImageData)
        }
    }
}

private extension PastrClip {
    func sharedCacheCopy(imageData: Data?) -> PastrClip {
        PastrClip(
            id: id,
            createdAt: createdAt,
            type: type,
            source: source,
            title: title,
            detail: detail,
            isPinned: isPinned,
            tintName: tintName,
            textContent: textContent,
            rtfData: nil,
            imageData: imageData,
            urlString: urlString,
            sourceAppBundleId: sourceAppBundleId,
            sourceAppName: sourceAppName,
            pinnedTitle: pinnedTitle,
            fingerprint: fingerprint,
            pasteboardRepresentations: [:],
            thumbnailName: thumbnailName
        )
    }
}
