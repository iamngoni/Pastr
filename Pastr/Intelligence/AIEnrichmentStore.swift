import Combine
import Foundation

/// Central coordinator for on-device clip intelligence. Owns per-clip `AIEnrichment`
/// records, runs the deterministic Tier 1 pipeline (OCR, classification, sensitivity,
/// embeddings) as clips arrive, and brokers Tier 2 (Apple Intelligence) requests.
///
/// All persistence is local (`ai-enrichment.json`); enrichment data is never synced.
final class AIEnrichmentStore: ObservableObject {
    static let shared = AIEnrichmentStore()

    /// Enrichment keyed by clip fingerprint.
    @Published private(set) var enrichments: [String: AIEnrichment] = [:]

    /// Cached model state for synchronous UI reads. The FoundationModels probe that updates
    /// this value always runs away from the main thread.
    @Published private(set) var appleIntelligenceAvailability: AppleIntelligenceAvailability = .checking

    private let settings = SettingsStore.shared
    private let persistence = AIEnrichmentPersistence()
    private let queue = DispatchQueue(label: "pastr.ai.enrichment", qos: .utility)
    private var availabilityTask: Task<Void, Never>?
    private var hasLoadedPersistence = false
    private var pendingItems: [String: ClipboardItem] = [:]

    private init() {
        persistence.loadAsync { [weak self] loaded in
            DispatchQueue.main.async {
                self?.finishLoading(loaded)
            }
        }
        if #available(macOS 26.0, *) {
            refreshAppleIntelligenceAvailability()
        } else {
            appleIntelligenceAvailability = .unsupportedOS
        }
    }

    deinit {
        availabilityTask?.cancel()
    }

    // MARK: - Lookup

    func enrichment(for fingerprint: String) -> AIEnrichment? {
        enrichments[fingerprint]
    }

    /// OCR / extracted text usable for search, if any.
    func searchableText(for fingerprint: String) -> String? {
        enrichments[fingerprint]?.searchableText
    }

    func sensitivity(for fingerprint: String) -> SensitivityLevel {
        enrichments[fingerprint]?.sensitivity ?? .none
    }

    func category(for fingerprint: String) -> ContentCategory? {
        enrichments[fingerprint]?.category
    }

    func tagSuggestions(for fingerprint: String) -> [String] {
        enrichments[fingerprint]?.tagSuggestions ?? []
    }

    // MARK: - Tier 1 pipeline

    /// Enrich a freshly captured clip. Cheap and idempotent: skips work that's already done
    /// or disabled. Runs off the main thread.
    func enrich(_ item: ClipboardItem) {
        guard settings.aiEnrichmentEnabled else { return }
        guard hasLoadedPersistence else {
            pendingItems[item.fingerprint] = item
            return
        }

        let existing = enrichments[item.fingerprint]
        if let existing, !existing.needsReprocessing, isComplete(existing, for: item) { return }

        let snapshot = SettingsSnapshot(settings)
        queue.async { [weak self] in
            guard let self else { return }
            let result = Self.runPipeline(item, settings: snapshot, existing: existing)
            DispatchQueue.main.async {
                self.enrichments[item.fingerprint] = result.enrichment
                self.persist()
                if snapshot.autoTagging {
                    self.applyAutoTags(result.enrichment, for: item)
                }
            }
        }
    }

    /// Re-run enrichment across a batch (e.g. on launch for clips missing data).
    func backfill(_ items: [ClipboardItem], limit: Int = 200) {
        guard settings.aiEnrichmentEnabled else { return }
        guard hasLoadedPersistence else {
            for item in items.prefix(limit) {
                pendingItems[item.fingerprint] = item
            }
            return
        }

        let pending = items.prefix(limit).filter { item in
            guard let e = enrichments[item.fingerprint] else { return true }
            return e.needsReprocessing || !isComplete(e, for: item)
        }
        guard !pending.isEmpty else { return }

        let existing = enrichments
        let snapshot = SettingsSnapshot(settings)
        queue.async { [weak self] in
            guard let self else { return }
            var completed: [String: AIEnrichment] = [:]
            completed.reserveCapacity(pending.count)
            for item in pending {
                let result = Self.runPipeline(
                    item,
                    settings: snapshot,
                    existing: existing[item.fingerprint]
                )
                completed[item.fingerprint] = result.enrichment
            }

            DispatchQueue.main.async {
                self.enrichments.merge(completed, uniquingKeysWith: { _, newest in newest })
                self.persist()
                if snapshot.autoTagging {
                    for item in pending {
                        if let enrichment = completed[item.fingerprint] {
                            self.applyAutoTags(enrichment, for: item)
                        }
                    }
                }
            }
        }
    }

    private func isComplete(_ e: AIEnrichment, for item: ClipboardItem) -> Bool {
        if item.type == .image, e.ocrText == nil { return false }
        if item.plainText != nil, e.embedding == nil, settings.semanticSearchEnabled { return false }
        return true
    }

    private static func runPipeline(
        _ item: ClipboardItem,
        settings: SettingsSnapshot,
        existing: AIEnrichment?
    ) -> (enrichment: AIEnrichment, isNew: Bool) {
        var enrichment = existing ?? AIEnrichment(fingerprint: item.fingerprint)
        enrichment.pipelineVersion = AIEnrichment.currentPipelineVersion

        // OCR for images.
        if settings.ocr, item.type == .image, enrichment.ocrText == nil,
           let data = item.imageData {
            enrichment.ocrText = OCRService.recognizeText(in: data)
        }

        // Text used for downstream text analysis (clip text, falling back to OCR text).
        let analyzableText = item.plainText ?? enrichment.ocrText

        // Classification + tag suggestions.
        let classification = ContentClassifier.classify(item)
        enrichment.category = classification.category
        enrichment.tagSuggestions = classification.tagSuggestions

        // Sensitivity.
        if settings.sensitiveDetection {
            enrichment.sensitivity = SensitiveDataDetector.sensitivity(of: analyzableText)
        } else {
            enrichment.sensitivity = .none
        }

        // Semantic embedding.
        if settings.semanticSearch, enrichment.embedding == nil {
            enrichment.embedding = SemanticIndex.embed(analyzableText)
        }

        return (enrichment, existing == nil)
    }

    private func applyAutoTags(_ enrichment: AIEnrichment, for item: ClipboardItem) {
        // Only auto-apply the single category tag to avoid noise; richer suggestions remain
        // available on demand in the context menu.
        guard let category = enrichment.category, category != .other else { return }
        let tagStore = TagStore.shared
        let name = category.label
        let existing = tagStore.tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let tag = existing ?? tagStore.create(name: name, color: Self.color(for: category))
        if !tagStore.hasTag(tag.id, fingerprint: item.fingerprint) {
            tagStore.addTag(tag.id, to: item.fingerprint)
        }
    }

    private static func color(for category: ContentCategory) -> String {
        switch category {
        case .code, .json, .command: return "#5E5CE6"
        case .url: return "#0A84FF"
        case .email, .phone, .address: return "#FF9F0A"
        case .number, .color: return "#30D158"
        default: return "#8E8E93"
        }
    }

    // MARK: - Semantic search

    /// Rank clips by semantic similarity to `query`. Returns fingerprint→score for clips
    /// above the match threshold, best first.
    func semanticMatches(for query: String, among items: [ClipboardItem]) async -> [(fingerprint: String, score: Float)] {
        guard settings.semanticSearchEnabled,
              query.trimmingCharacters(in: .whitespaces).count >= 3 else { return [] }

        // Capture only value types before leaving the main actor. No ClipboardItem, Core Data,
        // or ObservableObject state is touched by the detached scoring work.
        let vectors = items.compactMap { item -> (fingerprint: String, vector: [Float])? in
            guard let vector = enrichments[item.fingerprint]?.embedding else { return nil }
            return (item.fingerprint, vector)
        }

        return await Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let queryVector = SemanticIndex.embedQuery(query) else { return [] }

            var scored: [(fingerprint: String, score: Float)] = []
            scored.reserveCapacity(vectors.count)
            for (fingerprint, vector) in vectors {
                guard !Task.isCancelled else { return [] }
                let score = SemanticIndex.similarity(queryVector, vector)
                if score >= SemanticIndex.matchThreshold {
                    scored.append((fingerprint, score))
                }
            }
            return scored.sorted { $0.score > $1.score }
        }.value
    }

    // MARK: - Tier 2 (Apple Intelligence)

    /// Refresh the cached FoundationModels status without blocking the caller or SwiftUI.
    func refreshAppleIntelligenceAvailability() {
        guard #available(macOS 26.0, *) else {
            appleIntelligenceAvailability = .unsupportedOS
            return
        }
        guard availabilityTask == nil else { return }

        appleIntelligenceAvailability = .checking
        availabilityTask = Task { [weak self] in
            let availability = await AppleIntelligenceService.availability()
            await MainActor.run {
                guard let self else { return }
                if !Task.isCancelled {
                    self.appleIntelligenceAvailability = availability
                }
                self.availabilityTask = nil
            }
        }
    }

    /// Generate and cache a title for a clip.
    @discardableResult
    func generateTitle(for item: ClipboardItem) async throws -> String {
        guard let text = item.plainText ?? searchableText(for: item.fingerprint) else {
            throw AppleIntelligenceError.emptyInput
        }
        let title = try await AppleIntelligenceService.generateTitle(for: text)
        update(item.fingerprint) { $0.generatedTitle = title }
        return title
    }

    /// Summarise a clip and cache the result.
    @discardableResult
    func summarize(_ item: ClipboardItem) async throws -> String {
        guard let text = item.plainText ?? searchableText(for: item.fingerprint) else {
            throw AppleIntelligenceError.emptyInput
        }
        let summary = try await AppleIntelligenceService.summarize(text)
        update(item.fingerprint) { $0.summary = summary }
        return summary
    }

    /// Apply a "Paste as…" transform. Result is returned (not cached) for the caller to use.
    func transform(_ item: ClipboardItem, _ transform: TextTransform) async throws -> String {
        guard let text = item.plainText ?? searchableText(for: item.fingerprint) else {
            throw AppleIntelligenceError.emptyInput
        }
        return try await AppleIntelligenceService.transform(text, transform)
    }

    // MARK: - Maintenance

    func remove(fingerprint: String) {
        remove(fingerprints: [fingerprint])
    }

    func remove(fingerprints: Set<String>) {
        guard !fingerprints.isEmpty,
              fingerprints.contains(where: { enrichments[$0] != nil }) else { return }
        var updated = enrichments
        for fingerprint in fingerprints {
            updated.removeValue(forKey: fingerprint)
        }
        enrichments = updated
        persist()
    }

    /// Drop enrichment for clips no longer present in history.
    func prune(keeping fingerprints: Set<String>) {
        let before = enrichments.count
        enrichments = enrichments.filter { fingerprints.contains($0.key) }
        if enrichments.count != before { persist() }
    }

    // MARK: - Internals

    /// Mutate (creating if needed) the enrichment for a fingerprint on the main actor.
    @MainActor
    private func update(_ fingerprint: String, _ mutate: (inout AIEnrichment) -> Void) {
        var e = enrichments[fingerprint] ?? AIEnrichment(fingerprint: fingerprint)
        mutate(&e)
        enrichments[fingerprint] = e
        persist()
    }

    private func persist() {
        persistence.save(enrichments)
    }

    private func finishLoading(_ loaded: [String: AIEnrichment]) {
        guard !hasLoadedPersistence else { return }
        var merged = loaded
        merged.merge(enrichments, uniquingKeysWith: { _, current in current })
        enrichments = merged
        hasLoadedPersistence = true

        let queuedItems = Array(pendingItems.values)
        pendingItems.removeAll(keepingCapacity: false)
        backfill(queuedItems, limit: queuedItems.count)
    }
}

// MARK: - Settings snapshot

/// Immutable copy of the AI-relevant settings, captured on the main thread before handing
/// work to the background queue.
private struct SettingsSnapshot {
    let ocr: Bool
    let semanticSearch: Bool
    let sensitiveDetection: Bool
    let autoTagging: Bool

    init(_ s: SettingsStore) {
        ocr = s.ocrEnabled
        semanticSearch = s.semanticSearchEnabled
        sensitiveDetection = s.sensitiveDataDetectionEnabled
        autoTagging = s.autoTaggingEnabled
    }
}

// MARK: - Persistence

private final class AIEnrichmentPersistence {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "pastr.ai-enrichment.persistence", qos: .utility)
    private let stateLock = NSLock()
    private var pendingRecords: [AIEnrichment]?
    private var writerIsRunning = false

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Pastr", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("ai-enrichment.json")
    }

    func load() -> [String: AIEnrichment] {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let records = try? JSONDecoder().decode([AIEnrichment].self, from: data) else {
            return [:]
        }
        return Dictionary(records.map { ($0.fingerprint, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func loadAsync(completion: @escaping ([String: AIEnrichment]) -> Void) {
        queue.async { [weak self] in
            completion(self?.load() ?? [:])
        }
    }

    func save(_ enrichments: [String: AIEnrichment]) {
        let records = Array(enrichments.values)
        stateLock.lock()
        pendingRecords = records
        guard !writerIsRunning else {
            stateLock.unlock()
            return
        }
        writerIsRunning = true
        stateLock.unlock()

        queue.async { [weak self] in
            self?.drainPendingSaves()
        }
    }

    private func drainPendingSaves() {
        while true {
            stateLock.lock()
            guard let records = pendingRecords else {
                writerIsRunning = false
                stateLock.unlock()
                return
            }
            pendingRecords = nil
            stateLock.unlock()

            autoreleasepool {
                guard let data = try? JSONEncoder().encode(records) else { return }
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
