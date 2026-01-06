import AppKit

final class ClipboardActions {
    func copyToClipboard(_ item: ClipboardItem) {
        item.write(to: .general)
        SoundManager.playCopySound()
    }

    func openLink(_ item: ClipboardItem) {
        guard let urlString = item.urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)pa
    }

    func revealInFinder(_ item: ClipboardItem) {
        guard !item.fileURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs)
    }
}
