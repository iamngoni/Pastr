import AppKit
import Foundation

/// Caches parsed AttributedString objects to avoid expensive RTF parsing
/// and slow characterwiseIsEqual comparisons during SwiftUI layout.
final class AttributedStringCache {
    static let shared = AttributedStringCache()

    private var cache: [String: AttributedString] = [:]
    private let cacheQueue = DispatchQueue(label: "com.pastr.attributed-string-cache", attributes: .concurrent)

    private init() {}

    /// Returns a cached AttributedString for the given fingerprint, or nil if not cached.
    func cachedAttributedString(for fingerprint: String) -> AttributedString? {
        cacheQueue.sync {
            cache[fingerprint]
        }
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

        // Cache the result
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache[fingerprint] = attributed
        }

        return attributed
    }

    /// Removes cached entry for a fingerprint (e.g., when item is deleted).
    func removeAttributedString(for fingerprint: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeValue(forKey: fingerprint)
        }
    }

    /// Clears the entire cache.
    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}
