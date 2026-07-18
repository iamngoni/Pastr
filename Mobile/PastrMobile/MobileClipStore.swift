import Combine
import CoreData
import SwiftUI
import UIKit

@MainActor
final class MobileClipStore: ObservableObject {
    @Published private(set) var clips: [PastrClip]
    @Published private(set) var syncState: MobileSyncState = .idle
    @Published var userMessage: String?

    private let cloudStore: PastrCloudClipStore
    private let isScreenshotMode: Bool
    private var remoteChangeObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?

    init(
        cloudStore: PastrCloudClipStore = .shared,
        isScreenshotMode: Bool = ProcessInfo.processInfo.arguments.contains("-pastrScreenshotMode")
    ) {
        self.cloudStore = cloudStore
        self.isScreenshotMode = isScreenshotMode
        clips = isScreenshotMode ? PastrSampleClips.clips : PastrSharedClipCache.load()
        if !isScreenshotMode {
            observeStoreChanges()
        }
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        refreshTask?.cancel()
        mutationTask?.cancel()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshNow()
        }
    }

    func refreshNow() async {
        guard !isScreenshotMode else {
            syncState = .success
            return
        }

        syncState = .syncing
        do {
            let latest = try cloudStore.refreshSharedCache()
            clips = latest
            syncState = .success
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func captureCurrentPasteboard() {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            await self?.importCurrentPasteboard()
        }
    }

    func importCurrentPasteboard() async {
        guard let clip = PastrPasteboardImporter.clipFromCurrentPasteboard() else {
            userMessage = "No supported clipboard item"
            return
        }

        do {
            try cloudStore.upsert(clip)
            let latest = try cloudStore.refreshSharedCache()
            clips = latest
            userMessage = "Saved to Pastr"
            syncState = .success
        } catch {
            userMessage = error.localizedDescription
            syncState = .failed(error.localizedDescription)
        }
    }

    func delete(_ clip: PastrClip) {
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try cloudStore.remove(fingerprint: clip.fingerprint)
                let latest = try cloudStore.refreshSharedCache()
                clips = latest
            } catch {
                userMessage = error.localizedDescription
                syncState = .failed(error.localizedDescription)
            }
        }
    }

    private func observeStoreChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: cloudStore.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }
}

enum MobileSyncState: Equatable {
    case idle
    case syncing
    case success
    case failed(String)
}

enum PastrPasteboardImporter {
    private static let maxStoredImageBytes = 8 * 1024 * 1024
    private static let maxImagePixelDimension = 2_048
    private static let maxTextBytes = 512 * 1024

    static func clipFromCurrentPasteboard() -> PastrClip? {
        let pasteboard = UIPasteboard.general

        if let image = pasteboard.image,
           let data = normalizedPNGData(from: image) {
            return PastrClip(
                type: .image,
                source: "Clipboard",
                title: "Image",
                detail: "\(Int(image.size.width)) x \(Int(image.size.height)) px",
                imageData: data,
                sourceAppName: "iPhone Clipboard",
                pasteboardRepresentations: ["public.png": data]
            )
        }

        if let url = pasteboard.url {
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }

            return PastrClip(
                type: .link,
                source: "Clipboard",
                title: PastrClipText.title(for: .link, text: nil, url: url.absoluteString),
                detail: url.absoluteString,
                textContent: url.absoluteString,
                urlString: url.absoluteString,
                sourceAppName: "iPhone Clipboard",
                pasteboardRepresentations: [
                    "public.url": Data(url.absoluteString.utf8),
                    "public.utf8-plain-text": Data(url.absoluteString.utf8)
                ]
            )
        }

        if let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           text.utf8.count <= maxTextBytes {
            let detectedURL = URL(string: text)
            let detectedScheme = detectedURL?.scheme?.lowercased()
            let detectedWebURL = detectedScheme == "http" || detectedScheme == "https" ? detectedURL : nil
            let type: PastrClipType = detectedWebURL == nil ? .text : .link
            return PastrClip(
                type: type,
                source: "Clipboard",
                title: PastrClipText.title(
                    for: type,
                    text: text,
                    url: detectedWebURL?.absoluteString
                ),
                detail: PastrClipText.detail(
                    for: type,
                    text: text,
                    url: detectedWebURL?.absoluteString
                ),
                textContent: text,
                urlString: detectedWebURL?.absoluteString,
                sourceAppName: "iPhone Clipboard",
                pasteboardRepresentations: ["public.utf8-plain-text": Data(text.utf8)]
            )
        }

        return nil
    }

    private static func normalizedPNGData(from image: UIImage) -> Data? {
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > CGFloat(maxImagePixelDimension)
            ? CGFloat(maxImagePixelDimension) / largestSide
            : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = normalized.pngData(),
              data.count <= maxStoredImageBytes else { return nil }
        return data
    }
}
