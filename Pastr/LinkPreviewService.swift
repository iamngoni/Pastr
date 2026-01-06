import AppKit
import Combine
import Foundation
import LinkPresentation
import UniformTypeIdentifiers

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
              let url = URL(string: urlString) else {
            return
        }

        inFlightRequests.insert(urlString)

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.inFlightRequests.remove(urlString)

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
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
