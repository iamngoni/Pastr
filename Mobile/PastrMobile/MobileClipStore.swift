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
    }

    func refresh() {
        Task {
            await refreshNow()
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
        Task {
            await importCurrentPasteboard()
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
        Task {
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
            Task { @MainActor in
                self?.refresh()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
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
    static func clipFromCurrentPasteboard() -> PastrClip? {
        let pasteboard = UIPasteboard.general

        if let image = pasteboard.image,
           let data = image.pngData() {
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
           !text.isEmpty {
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
}
