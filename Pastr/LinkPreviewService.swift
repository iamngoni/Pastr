import AppKit
import Combine
import Foundation
import LinkPresentation
import UniformTypeIdentifiers

final class LinkPreviewService: ObservableObject {
    static let shared = LinkPreviewService()

    @Published private(set) var previews: [String: LinkPreview] = [:]
    private var inFlightRequests: Set<String> = []
    private var providers: [String: LPMetadataProvider] = [:]
    private let cache = NSCache<NSString, LinkPreview>()

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
              let url = normalizedURL(from: urlString) else {
            return
        }

        inFlightRequests.insert(urlString)

        let provider = LPMetadataProvider()
        providers[urlString] = provider
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.inFlightRequests.remove(urlString)
                self.providers[urlString] = nil

                if let metadata = metadata {
                    let preview = LinkPreview(
                        url: urlString,
                        title: metadata.title,
                        siteName: self.extractDomain(from: urlString)
                    )

                    self.previews[urlString] = preview

                    // Load the main preview image (Open Graph image)
                    if let imageProvider = metadata.imageProvider {
                        self.loadImage(from: imageProvider, for: urlString, isIcon: false)
                    } else {
                        self.fetchOpenGraphImage(from: url, for: urlString)
                    }

                    // Also load the icon/favicon
                    if let iconProvider = metadata.iconProvider {
                        self.loadImage(from: iconProvider, for: urlString, isIcon: true)
                    }
                } else {
                    let preview = LinkPreview(
                        url: urlString,
                        title: nil,
                        siteName: self.extractDomain(from: urlString)
                    )
                    self.previews[urlString] = preview
                    self.fetchOpenGraphImage(from: url, for: urlString)
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider, for urlString: String, isIcon: Bool) {
        // Try loading as NSImage first
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { [weak self] image, error in
                if let nsImage = image as? NSImage {
                    self?.updatePreview(urlString: urlString, image: nsImage, isIcon: isIcon)
                    return
                }
                // If NSImage fails, try data approach
                self?.loadImageAsData(from: provider, for: urlString, isIcon: isIcon)
            }
        } else {
            // Try loading as raw data
            loadImageAsData(from: provider, for: urlString, isIcon: isIcon)
        }
    }

    private func loadImageAsData(from provider: NSItemProvider, for urlString: String, isIcon: Bool) {
        // Try common image types
        let imageTypes = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.gif.identifier,
            UTType.webP.identifier,
            UTType.image.identifier,
            "public.image"
        ]

        for typeIdentifier in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
                    guard let data = data, let nsImage = NSImage(data: data) else { return }
                    self?.updatePreview(urlString: urlString, image: nsImage, isIcon: isIcon)
                }
                return
            }
        }

        // Last resort: try loading file representation
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            guard let url = url, let nsImage = NSImage(contentsOf: url) else { return }
            self?.updatePreview(urlString: urlString, image: nsImage, isIcon: isIcon)
        }
    }

    private func updatePreview(urlString: String, image: NSImage, isIcon: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let preview = self.previews[urlString] {
                if isIcon {
                    preview.icon = image
                } else {
                    preview.image = image
                }
                self.previews[urlString] = preview
                self.cache.setObject(preview, forKey: urlString as NSString)
            }
        }
    }

    private func extractDomain(from urlString: String) -> String {
        if let url = URL(string: urlString),
           let host = url.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if let url = URL(string: "https://\(urlString)"),
           let host = url.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return urlString
    }

    private func normalizedURL(from urlString: String) -> URL? {
        if let url = URL(string: urlString), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(urlString)")
    }

    private func fetchOpenGraphImage(from url: URL, for urlString: String) {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data else { return }
            guard let html = String(data: data, encoding: .utf8) else { return }

            if let imageURL = self.extractOpenGraphImageURL(from: html, baseURL: url) {
                self.fetchImageData(from: imageURL, for: urlString)
            }
        }.resume()
    }

    private func extractOpenGraphImageURL(from html: String, baseURL: URL) -> URL? {
        let candidates = [
            extractMetaContent(from: html, property: "og:image"),
            extractMetaContent(from: html, property: "twitter:image")
        ]

        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            if let url = URL(string: value) {
                return url
            }
            if let url = URL(string: value, relativeTo: baseURL) {
                return url.absoluteURL
            }
        }
        return nil
    }

    private func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']\(property)[\"'][^>]*>",
            "<meta[^>]+name=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+name=[\"']\(property)[\"'][^>]*>"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    private func fetchImageData(from url: URL, for urlString: String) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let image = NSImage(data: data) else { return }
            self.updatePreview(urlString: urlString, image: image, isIcon: false)
        }.resume()
    }
}

final class LinkPreview: NSObject {
    let url: String
    let title: String?
    let siteName: String
    var icon: NSImage?
    var image: NSImage?

    init(url: String, title: String?, siteName: String) {
        self.url = url
        self.title = title
        self.siteName = siteName
        super.init()
    }
}
