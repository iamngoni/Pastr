import AppKit

/// Thread-safe cache for app icons to prevent UI hangs when loading icons
final class AppIconCache {
    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    private let cacheQueue = DispatchQueue(label: "com.pastr.icon-cache", attributes: .concurrent)
    private let loadQueue = DispatchQueue(label: "com.pastr.icon-load", qos: .userInitiated)

    private init() {}

    /// Returns cached icon synchronously, or nil if not cached yet
    func cachedIcon(for bundleId: String) -> NSImage? {
        cacheQueue.sync {
            cache[bundleId]
        }
    }

    /// Loads icon asynchronously, using cache if available
    func icon(for bundleId: String, completion: @escaping (NSImage?) -> Void) {
        // Check cache first
        if let cached = cachedIcon(for: bundleId) {
            completion(cached)
            return
        }

        // Load on background thread
        loadQueue.async { [weak self] in
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let icon = NSWorkspace.shared.icon(forFile: appURL.path)

            // Cache the icon
            self?.cacheQueue.async(flags: .barrier) {
                self?.cache[bundleId] = icon
            }

            DispatchQueue.main.async { completion(icon) }
        }
    }

    /// Preloads icon into cache without callback
    func preloadIcon(for bundleId: String) {
        guard cachedIcon(for: bundleId) == nil else { return }
        icon(for: bundleId) { _ in }
    }

    /// Clears the cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}
