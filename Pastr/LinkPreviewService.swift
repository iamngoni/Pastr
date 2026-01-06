import AppKit
import Combine
import Foundation
import OpenGraph

final class LinkPreviewService: ObservableObject {
    static let shared = LinkPreviewService()

    @Published private(set) var previews: [String: LinkPreview] = [:]
    private var inFlightRequests: Set<String> = []
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

        // Create initial preview immediately with domain
        let initialPreview = LinkPreview(
            url: urlString,
            title: nil,
            siteName: extractDomain(from: urlString)
        )
        DispatchQueue.main.async {
            self.previews[urlString] = initialPreview
        }

        // Use OpenGraph library to fetch metadata
        Task {
            do {
                let og = try await OpenGraph.fetch(url: url)
                await MainActor.run {
                    self.inFlightRequests.remove(urlString)

                    let preview = LinkPreview(
                        url: urlString,
                        title: og[.title],
                        siteName: og[.siteName] ?? self.extractDomain(from: urlString)
                    )
                    self.previews[urlString] = preview

                    // Fetch the OG image
                    if let imageURLString = og[.image], let imageURL = URL(string: imageURLString) {
                        self.fetchImage(from: imageURL, for: urlString, isIcon: false)
                    }

                    // Try to fetch favicon
                    self.fetchFavicon(for: url, urlString: urlString)
                }
            } catch {
                await MainActor.run {
                    self.inFlightRequests.remove(urlString)
                    // Keep the initial preview with just the domain
                    self.fetchFavicon(for: url, urlString: urlString)
                }
            }
        }
    }

    private func fetchImage(from imageURL: URL, for urlString: String, isIcon: Bool) {
        var request = URLRequest(url: imageURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, let image = NSImage(data: data) else { return }
            self.updatePreview(urlString: urlString, image: image, isIcon: isIcon)
        }.resume()
    }

    private func fetchFavicon(for url: URL, urlString: String) {
        // Try common favicon locations
        guard let host = url.host,
              let scheme = url.scheme else { return }

        let faviconURLs = [
            URL(string: "\(scheme)://\(host)/favicon.ico"),
            URL(string: "\(scheme)://\(host)/apple-touch-icon.png"),
            URL(string: "\(scheme)://\(host)/apple-touch-icon-precomposed.png"),
            URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
        ].compactMap { $0 }

        tryFetchingFavicon(from: faviconURLs, for: urlString, index: 0)
    }

    private func tryFetchingFavicon(from urls: [URL], for urlString: String, index: Int) {
        guard index < urls.count else { return }

        var request = URLRequest(url: urls[index])
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let data = data, let image = NSImage(data: data), image.size.width > 0 {
                self.updatePreview(urlString: urlString, image: image, isIcon: true)
            } else {
                // Try next favicon URL
                self.tryFetchingFavicon(from: urls, for: urlString, index: index + 1)
            }
        }.resume()
    }

    private func updatePreview(urlString: String, image: NSImage, isIcon: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if var preview = self.previews[urlString] {
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
