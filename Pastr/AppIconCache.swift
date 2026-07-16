import AppKit

/// Thread-safe cache for app icons to prevent UI hangs when loading icons
final class AppIconCache {
    static let shared = AppIconCache()

    private let loadQueue = DispatchQueue(label: "com.pastr.icon-load", qos: .userInitiated)
    private let cache = NSCache<NSString, NSImage>()
    private let stateLock = NSLock()
    private var inFlightCompletions: [String: [(NSImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    /// Returns cached icon synchronously, or nil if not cached yet
    func cachedIcon(for bundleId: String) -> NSImage? {
        cache.object(forKey: bundleId as NSString)
    }

    /// Loads icon asynchronously, using cache if available
    func icon(for bundleId: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = cachedIcon(for: bundleId) {
            completion(cached)
            return
        }

        stateLock.lock()
        if inFlightCompletions[bundleId] != nil {
            inFlightCompletions[bundleId]?.append(completion)
            stateLock.unlock()
            return
        }
        inFlightCompletions[bundleId] = [completion]
        stateLock.unlock()

        loadQueue.async { [weak self] in
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                self?.completeLoad(for: bundleId, icon: nil)
                return
            }

            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            self?.cache.setObject(icon, forKey: bundleId as NSString)
            self?.completeLoad(for: bundleId, icon: icon)
        }
    }

    /// Preloads icon into cache without callback
    func preloadIcon(for bundleId: String) {
        guard cachedIcon(for: bundleId) == nil else { return }
        icon(for: bundleId) { _ in }
    }

    /// Clears the cache
    func clearCache() {
        cache.removeAllObjects()
    }

    private func completeLoad(for bundleId: String, icon: NSImage?) {
        stateLock.lock()
        let completions = inFlightCompletions.removeValue(forKey: bundleId) ?? []
        stateLock.unlock()

        DispatchQueue.main.async {
            completions.forEach { $0(icon) }
        }
    }
}
