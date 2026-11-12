import AppKit
import Combine

/// Thread-safe cache for app icons to prevent UI hangs when loading icons.
///
/// UI usage: observe `AppIconCache.shared` (`@ObservedObject`) and call
/// `icon(forBundleID:)` from the view body. It returns the cached icon immediately, or nil
/// while kicking off a background load; `revision` is published when a load finishes so the
/// view re-renders and the next call returns the icon.
final class AppIconCache: ObservableObject {
    static let shared = AppIconCache()

    /// Incremented (on the main thread) whenever a new icon becomes available.
    @Published private(set) var revision: Int = 0

    private let loadQueue = DispatchQueue(label: "com.pastr.icon-load", qos: .userInitiated)
    private let cache = NSCache<NSString, NSImage>()
    private let stateLock = NSLock()
    private var inFlightCompletions: [String: [(NSImage?) -> Void]] = [:]
    /// Bundle ids that could not be resolved; avoids re-querying on every redraw.
    private var unresolvedBundleIDs: Set<String> = []

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    /// Cached icon, or nil while it loads in the background (then `revision` publishes).
    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cachedIcon(for: bundleID) {
            return cached
        }
        stateLock.lock()
        let known = unresolvedBundleIDs.contains(bundleID)
        stateLock.unlock()
        if !known {
            preloadIcon(for: bundleID)
        }
        return nil
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
        stateLock.lock()
        unresolvedBundleIDs.removeAll()
        stateLock.unlock()
    }

    private func completeLoad(for bundleId: String, icon: NSImage?) {
        stateLock.lock()
        let completions = inFlightCompletions.removeValue(forKey: bundleId) ?? []
        if icon == nil { unresolvedBundleIDs.insert(bundleId) }
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            if icon != nil { self?.revision += 1 }
            completions.forEach { $0(icon) }
        }
    }
}
