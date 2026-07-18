import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private var saveTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()

        saveTask = Task { [weak self] in
            await self?.saveSharedClip()
        }
    }

    deinit {
        saveTask?.cancel()
        closeTask?.cancel()
    }

    private func configureView() {
        view.backgroundColor = UIColor.systemBackground
        statusLabel.text = "Saving to Pastr..."
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @MainActor
    private func saveSharedClip() async {
        do {
            guard let clip = await firstSharedClip() else {
                statusLabel.text = "No supported item"
                closeAfterDelay()
                return
            }

            let store = PastrCloudClipStore()
            try store.upsert(clip)
            try store.refreshSharedCache()
            statusLabel.text = "Saved to Pastr"
            closeAfterDelay()
        } catch {
            statusLabel.text = error.localizedDescription
            closeAfterDelay()
        }
    }

    private func firstSharedClip() async -> PastrClip? {
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        for item in inputItems {
            for provider in item.attachments ?? [] {
                if let clip = await ShareClipExtractor.clip(from: provider) {
                    return clip
                }
            }
        }

        return nil
    }

    private func closeAfterDelay() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}

private enum ShareClipExtractor {
    private static let maxInputImageBytes = 25 * 1024 * 1024
    private static let maxStoredImageBytes = 8 * 1024 * 1024
    private static let maxTextBytes = 512 * 1024
    private static let maxImagePixelDimension = 2_048

    static func clip(from provider: NSItemProvider) async -> PastrClip? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let imageData = await loadImageData(from: provider) {
            return makeImageClip(imageData)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(from: provider, typeIdentifier: UTType.url.identifier),
           let clip = makeURLClip(url) {
            return clip
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadString(from: provider, typeIdentifier: UTType.plainText.identifier) {
            return makeTextClip(text)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(from: provider, typeIdentifier: UTType.fileURL.identifier) {
            if let imageData = imageData(from: url) {
                return makeImageClip(imageData, title: url.deletingPathExtension().lastPathComponent)
            }

            return PastrClip(
                type: .file,
                source: "Share",
                title: url.lastPathComponent,
                detail: url.path,
                textContent: url.lastPathComponent,
                sourceAppName: "Share Extension"
            )
        }

        return nil
    }

    private static func makeImageClip(_ imageData: Data, title: String = "Image") -> PastrClip {
        let imageSize = imageDimensions(from: imageData)
        let detail: String
        if let size = imageSize {
            detail = "\(Int(size.width)) x \(Int(size.height)) px"
        } else {
            detail = "Shared image"
        }

        return PastrClip(
            type: .image,
            source: "Share",
            title: title.isEmpty ? "Image" : title,
            detail: detail,
            imageData: imageData,
            sourceAppName: "Share Extension",
            pasteboardRepresentations: ["public.png": imageData]
        )
    }

    private static func makeURLClip(_ url: URL) -> PastrClip? {
        guard url.isWebURL else {
            return nil
        }

        return PastrClip(
            type: .link,
            source: "Share",
            title: PastrClipText.title(for: .link, text: nil, url: url.absoluteString),
            detail: url.absoluteString,
            textContent: url.absoluteString,
            urlString: url.absoluteString,
            sourceAppName: "Share Extension",
            pasteboardRepresentations: [
                "public.url": Data(url.absoluteString.utf8),
                "public.utf8-plain-text": Data(url.absoluteString.utf8)
            ]
        )
    }

    private static func makeTextClip(_ text: String) -> PastrClip? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let detectedURL = URL(string: trimmed)
        let detectedWebURL = detectedURL?.isWebURL == true ? detectedURL : nil
        let type: PastrClipType = detectedWebURL == nil ? .text : .link
        return PastrClip(
            type: type,
            source: "Share",
            title: PastrClipText.title(for: type, text: trimmed, url: detectedWebURL?.absoluteString),
            detail: PastrClipText.detail(for: type, text: trimmed, url: detectedWebURL?.absoluteString),
            textContent: trimmed,
            urlString: detectedWebURL?.absoluteString,
            sourceAppName: "Share Extension",
            pasteboardRepresentations: ["public.utf8-plain-text": Data(trimmed.utf8)]
        )
    }

    private static func loadString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        guard let item = try? await provider.loadItem(typeIdentifier: typeIdentifier) else {
            return nil
        }

        if let string = item as? String {
            return string
        }
        if let data = item as? Data {
            guard data.count <= maxTextBytes else { return nil }
            return String(data: data, encoding: .utf8)
        }
        if let url = item as? URL {
            return stringFromFile(url)
        }
        return nil
    }

    private static func loadURL(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        guard let item = try? await provider.loadItem(typeIdentifier: typeIdentifier) else {
            return nil
        }

        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        let imageTypeIdentifiers = provider.registeredTypeIdentifiers.filter { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
        let preferredTypeIdentifiers = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.heic.identifier,
            UTType.image.identifier
        ] + imageTypeIdentifiers

        for typeIdentifier in Array(Set(preferredTypeIdentifiers)) {
            if let data = try? await provider.loadData(typeIdentifier: typeIdentifier),
               let pngData = normalizedImageData(from: data) {
                return pngData
            }
        }

        guard let item = try? await provider.loadItem(typeIdentifier: UTType.image.identifier) else {
            return nil
        }

        if let image = item as? UIImage {
            return normalizedImageData(from: image)
        }
        if let data = item as? Data {
            return normalizedImageData(from: data)
        }
        if let url = item as? URL {
            return imageData(from: url)
        }
        return nil
    }

    private static func imageData(from url: URL) -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard fileSize(at: url) <= maxInputImageBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return normalizedImageData(from: source)
    }

    private static func stringFromFile(_ url: URL) -> String? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard fileSize(at: url) <= maxTextBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
    }

    private static func imageDimensions(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func normalizedImageData(from data: Data) -> Data? {
        guard data.count <= maxInputImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return normalizedImageData(from: source)
    }

    private static func normalizedImageData(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImagePixelDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        guard let pngData = image.pngData(),
              pngData.count <= maxStoredImageBytes else { return nil }
        return pngData
    }

    private static func normalizedImageData(from image: UIImage) -> Data? {
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > CGFloat(maxImagePixelDimension)
            ? CGFloat(maxImagePixelDimension) / largestSide
            : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let pngData = resized.pngData(),
              pngData.count <= maxStoredImageBytes else { return nil }
        return pngData
    }
}

private extension URL {
    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

private extension NSItemProvider {
    func loadItem(typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    func loadData(typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                }
            }
        }
    }
}
