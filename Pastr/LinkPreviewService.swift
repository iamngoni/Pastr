import AppKit
import Combine
import Foundation
import LinkPresentation

final class LinkPreviewService: ObservableObject {
    static let shared = LinkPreviewService()

    @Published private(set) var previews: [String: LinkPreview] = [:]
    private var inFlightRequests: Set<String> = []
    private let cache = NSCache<NSString, LinkPreview>()
    private let queue = DispatchQueue(label: "link-preview", qos: .userInitiated)

    private init() {
        cache.countLimit = 200
    }

    func preview(for urlString: String) -> LinkPreview? {
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached
        }
        return previews[urlString]
    }

    func fetchPreview(for urlString: String) {
        guard !inFlightRequests.contains(urlString),
              previews[urlString] == nil,
              cache.object(forKey: urlString as NSString) == nil,
              let url = URL(string: urlString) else {
            return
        }

        inFlightRequests.insert(urlString)

        // Use LPMetadataProvider for rich previews
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.inFlightRequests.remove(urlString)

                if let metadata = metadata {
                    let preview = LinkPreview(
                        url: urlString,
                        title: metadata.title,
                        siteName: self.extractDomain(from: urlString),
                        iconProvider: metadata.iconProvider
                    )

                    self.cache.setObject(preview, forKey: urlString as NSString)
                    self.previews[urlString] = preview

                    // Fetch icon asynchronously
                    if let iconProvider = metadata.iconProvider {
                        self.loadIcon(from: iconProvider, for: urlString)
                    }
                } else {
                    // Fallback: create basic preview from URL
                    let preview = LinkPreview(
                        url: urlString,
                        title: nil,
                        siteName: self.extractDomain(from: urlString),
                        iconProvider: nil
                    )
                    self.cache.setObject(preview, forKey: urlString as NSString)
                    self.previews[urlString] = preview
                }
            }
        }
    }

    private func loadIcon(from provider: NSItemProvider, for urlString: String) {
        provider.loadObject(ofClass: NSImage.self) { [weak self] image, _ in
            guard let self = self, let nsImage = image as? NSImage else { return }

            DispatchQueue.main.async {
                if var preview = self.previews[urlString] {
                    preview.icon = nsImage
                    self.previews[urlString] = preview
                    self.cache.setObject(preview, forKey: urlString as NSString)
                }
            }
        }
    }

    private func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        // Remove www. prefix if present
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

final class LinkPreview: NSObject {
    let url: String
    let title: String?
    let siteName: String
    var icon: NSImage?
    let iconProvider: NSItemProvider?

    init(url: String, title: String?, siteName: String, iconProvider: NSItemProvider?) {
        self.url = url
        self.title = title
        self.siteName = siteName
        self.iconProvider = iconProvider
        super.init()
    }
}
