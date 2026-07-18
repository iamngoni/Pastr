import AppKit
import Combine
import SwiftUI

/// Drives the panel's AI context-menu actions and surfaces a transient status banner.
/// Keeps async Apple Intelligence work out of the SwiftUI view layer.
@MainActor
final class PanelAIController: ObservableObject {
    struct Banner: Identifiable, Equatable {
        enum Kind: Equatable { case progress, success, error }
        let id = UUID()
        var message: String
        var kind: Kind
    }

    @Published var banner: Banner?

    private let store = AIEnrichmentStore.shared
    private let history = ClipboardHistoryStore.shared
    private let tagStore = TagStore.shared
    private var dismissTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    deinit {
        dismissTask?.cancel()
        actionTask?.cancel()
    }

    // MARK: - Tier 1 actions

    /// Copy text recognised in an image clip to the clipboard.
    func copyRecognizedText(_ item: ClipboardItem) {
        guard let text = store.searchableText(for: item.fingerprint), !text.isEmpty else {
            show("No recognized text", kind: .error)
            return
        }
        writeToClipboard(text)
        show("Copied recognized text", kind: .success)
    }

    /// Apply the classifier's suggested tags to a clip.
    func applySuggestedTags(_ item: ClipboardItem) {
        let suggestions = store.tagSuggestions(for: item.fingerprint)
        guard !suggestions.isEmpty else {
            show("No tag suggestions", kind: .error)
            return
        }
        var added = 0
        for name in suggestions {
            let existing = tagStore.tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            let tag = existing ?? tagStore.create(name: name)
            if !tagStore.hasTag(tag.id, fingerprint: item.fingerprint) {
                tagStore.addTag(tag.id, to: item.fingerprint)
                added += 1
            }
        }
        show(added > 0 ? "Added \(added) tag\(added == 1 ? "" : "s")" : "Tags already applied", kind: .success)
    }

    // MARK: - Tier 2 actions (Apple Intelligence)

    var appleIntelligenceAvailable: Bool { store.appleIntelligenceAvailability.isAvailable }

    func generateTitle(for item: ClipboardItem) {
        run("Generating title…") { [store, history] in
            let title = try await store.generateTitle(for: item)
            history.updatePinnedTitle(for: item, title: title)
            return "Titled: \(title)"
        }
    }

    func summarize(_ item: ClipboardItem) {
        run("Summarizing…") { [store] in
            let summary = try await store.summarize(item)
            Self.writeToClipboardStatic(summary)
            return "Summary copied to clipboard"
        }
    }

    func transform(_ item: ClipboardItem, _ transform: TextTransform) {
        run(transform.label + "…") { [store] in
            let result = try await store.transform(item, transform)
            Self.writeToClipboardStatic(result)
            return "Result copied to clipboard"
        }
    }

    // MARK: - Plumbing

    private func run(_ progress: String, _ work: @escaping () async throws -> String) {
        show(progress, kind: .progress, autoDismiss: false)
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            do {
                let message = try await work()
                self?.show(message, kind: .success)
            } catch {
                self?.show(error.localizedDescription, kind: .error)
            }
        }
    }

    private func show(_ message: String, kind: Banner.Kind, autoDismiss: Bool = true) {
        banner = Banner(message: message, kind: kind)
        dismissTask?.cancel()
        guard autoDismiss else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    private func writeToClipboard(_ text: String) {
        Self.writeToClipboardStatic(text)
    }

    private static func writeToClipboardStatic(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
