import AppKit
import Combine

final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var items: [ClipboardItem] = []

    private let settings = SettingsStore.shared
    private let persistence = HistoryPersistence()
    private let pinnedStore = PinnedStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        items = persistence.load()
        bindSettings()
    }

    func add(_ item: ClipboardItem) {
        if let existingIndex = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let existing = items[existingIndex]
            var updated = item
            updated.isPinned = existing.isPinned
            updated.pinnedTitle = existing.pinnedTitle
            items.remove(at: existingIndex)
            items.insert(updated, at: 0)
        } else {
            items.insert(item, at: 0)
        }

        prune()
        persistence.save(items)
    }

    func items(for section: PanelSection) -> [ClipboardItem] {
        switch section {
        case .history:
            return items
        case .pinned:
            return items.filter { $0.isPinned }
        }
    }

    func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        if updated.isPinned {
            updated.isPinned = false
            items[index] = updated
            pinnedStore.removePinned(fingerprint: updated.fingerprint)
        } else {
            let currentPinned = items.filter { $0.isPinned }.count
            if currentPinned >= settings.pinLimit {
                NSSound.beep()
                return
            }
            updated.isPinned = true
            items[index] = updated
            pinnedStore.savePinned(updated)
        }
        persistence.save(items)
    }

    func updatePinnedTitle(for item: ClipboardItem, title: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.pinnedTitle = title
        items[index] = updated
        if updated.isPinned {
            pinnedStore.savePinned(updated)
        }
        persistence.save(items)
    }

    func mergePinned(_ pinnedItems: [ClipboardItem]) {
        for pinned in pinnedItems {
            if let index = items.firstIndex(where: { $0.fingerprint == pinned.fingerprint }) {
                var updated = items[index]
                updated.isPinned = true
                updated.pinnedTitle = pinned.pinnedTitle
                items[index] = updated
            } else {
                items.insert(pinned, at: 0)
            }
        }
        persistence.save(items)
    }

    private func prune() {
        if !settings.historyUnlimited {
            let cutoff = Calendar.current.date(byAdding: .day, value: -settings.historyMaxDays, to: Date())
            if let cutoff {
                items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
            }

            if items.count > settings.historyMaxItems {
                let pinnedCount = items.filter { $0.isPinned }.count
                let allowedUnpinned = max(settings.historyMaxItems - pinnedCount, 0)
                var trimmed: [ClipboardItem] = []
                var unpinnedCount = 0
                for item in items {
                    if item.isPinned {
                        trimmed.append(item)
                    } else if unpinnedCount < allowedUnpinned {
                        trimmed.append(item)
                        unpinnedCount += 1
                    }
                }
                items = trimmed
            }
        }
    }

    private func bindSettings() {
        Publishers.CombineLatest3(settings.$historyMaxItems, settings.$historyMaxDays, settings.$historyUnlimited)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                self.prune()
                self.persistence.save(self.items)
            }
            .store(in: &cancellables)
    }
}
