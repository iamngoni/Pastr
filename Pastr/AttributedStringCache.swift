import AppKit
import Foundation

/// Caches parsed AttributedString objects to avoid expensive RTF parsing
/// and slow characterwiseIsEqual comparisons during SwiftUI layout.
final class AttributedStringCache {
    static let shared = AttributedStringCache()

    private final class Entry {
        let value: AttributedString

        init(_ value: AttributedString) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, Entry>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// Returns a cached AttributedString for the given fingerprint, or nil if not cached.
    func cachedAttributedString(for fingerprint: String) -> AttributedString? {
        cache.object(forKey: fingerprint as NSString)?.value
    }

    /// Parses RTF data and caches the result. Returns the parsed AttributedString or nil if parsing fails.
    func attributedString(for fingerprint: String, rtfData: Data) -> AttributedString? {
        // Check cache first
        if let cached = cachedAttributedString(for: fingerprint) {
            return cached
        }

        // Parse RTF data
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        guard let nsAttributed = try? NSAttributedString(data: rtfData, options: options, documentAttributes: nil) else {
            return nil
        }

        let attributed = AttributedString(nsAttributed)

        cache.setObject(Entry(attributed), forKey: fingerprint as NSString, cost: rtfData.count)

        return attributed
    }

    /// Removes cached entry for a fingerprint (e.g., when item is deleted).
    func removeAttributedString(for fingerprint: String) {
        cache.removeObject(forKey: fingerprint as NSString)
    }

    /// Clears the entire cache.
    func clearCache() {
        cache.removeAllObjects()
    }
}
