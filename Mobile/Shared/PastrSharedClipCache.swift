import Foundation

enum PastrSharedClipCache {
    static func load(limit: Int? = nil) -> [PastrClip] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url) else {
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
        let data = try encoder.encode(Array(clips.filter { !$0.isTransientFileProviderLink }.prefix(limit)))
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
}
