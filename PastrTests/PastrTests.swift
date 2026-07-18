//
//  PastrTests.swift
//  PastrTests
//
//  Created by Ngonidzashe  Mangudya on 2026/01/06.
//

import XCTest
@testable import Pastr

final class PastrTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPersonalDataClassifiesAsLowSensitivity() {
        let sensitivity = SensitiveDataDetector.sensitivity(of: "Contact me at person@example.com")

        XCTAssertEqual(sensitivity, .low)
    }

    func testShortSecretPrefixFragmentsAreNotSensitive() {
        let sensitivity = SensitiveDataDetector.sensitivity(of: "Safari copied a task-card screenshot")

        XCTAssertEqual(sensitivity, .none)
    }

    func testRealisticSecretClassifiesAsHighSensitivity() {
        let sensitivity = SensitiveDataDetector.sensitivity(
            of: "OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz1234567890"
        )

        XCTAssertEqual(sensitivity, .high)
    }

    func testPinnedStoreUsesLocalFallbackInTestHost() throws {
        XCTAssertFalse(PinnedStore.shared.isCloudSyncAvailable)
        XCTAssertNoThrow(try PinnedStore.shared.fetchAll())
    }

    func testPinnedStoreBatchesUpsertsAndRemovals() throws {
        let store = PinnedStore.shared
        try store.removeAll()
        defer { try? store.removeAll() }

        let items = (0..<120).map { index in
            makeClipboardItem(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 1_785_000_000 + Double(index)),
                textContent: "item \(index)",
                fingerprint: "batch-\(index)"
            )
        }
        try store.upsert(items)
        XCTAssertEqual(Set(try store.fetchAll().map(\.fingerprint)), Set(items.map(\.fingerprint)))

        let removedFingerprints = items.prefix(70).map(\.fingerprint)
        try store.remove(fingerprints: removedFingerprints)
        XCTAssertEqual(Set(try store.fetchAll().map(\.fingerprint)), Set(items.dropFirst(70).map(\.fingerprint)))
    }

    func testClipboardItemEqualityIgnoresHeavyPayloadBytes() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_785_000_000)
        let left = makeClipboardItem(
            id: id,
            createdAt: createdAt,
            rtfData: Data(repeating: 1, count: 1024),
            imageData: Data(repeating: 2, count: 2048)
        )
        let right = makeClipboardItem(
            id: id,
            createdAt: createdAt,
            rtfData: Data(repeating: 3, count: 1024),
            imageData: Data(repeating: 4, count: 2048)
        )

        XCTAssertEqual(left, right)
        XCTAssertEqual(left.hashValue, right.hashValue)
    }

    func testClipboardItemEqualityTracksDisplayMetadata() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_785_000_000)
        let left = makeClipboardItem(id: id, createdAt: createdAt, pinnedTitle: "One")
        let right = makeClipboardItem(id: id, createdAt: createdAt, pinnedTitle: "Two")

        XCTAssertNotEqual(left, right)
    }

    func testDisplayPreviewsAreBoundedWithoutChangingClipboardPayload() {
        let payload = String(repeating: "func example() { return 42 }\n", count: 5_000)
        let item = makeClipboardItem(
            id: UUID(),
            createdAt: Date(),
            textContent: payload,
            fingerprint: "large-preview"
        )

        XCTAssertLessThanOrEqual(item.cardPreviewText.count, ClipboardItem.cardPreviewCharacterLimit + 2)
        XCTAssertLessThanOrEqual(item.detailPreviewText.count, ClipboardItem.detailPreviewCharacterLimit + 2)
        XCTAssertTrue(item.cardPreviewText.hasSuffix("\n…"))
        XCTAssertTrue(item.detailPreviewText.hasSuffix("\n…"))
        XCTAssertEqual(item.textContent, payload)
        XCTAssertEqual(item.plainText, payload)
    }

    func testHistoryPersistenceCoalescesToNewestSnapshot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let persistence = HistoryPersistence(fileURL: folder.appendingPathComponent("history.json"))
        for index in 0..<100 {
            persistence.save([
                makeClipboardItem(
                    id: UUID(),
                    createdAt: Date(timeIntervalSince1970: Double(index)),
                    textContent: "snapshot \(index)",
                    fingerprint: "snapshot-\(index)"
                )
            ])
        }
        persistence.waitForPendingWrites()

        let loaded = persistence.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.textContent, "snapshot 99")
        XCTAssertEqual(loaded.first?.fingerprint, "snapshot-99")
    }

    func testSemanticEmbeddingSerializesConcurrentRequests() async throws {
        guard SemanticIndex.isAvailable else {
            throw XCTSkip("Natural Language sentence embeddings are unavailable on this Mac")
        }

        let vectors = await withTaskGroup(of: [Float]?.self, returning: [[Float]?].self) { group in
            for index in 0..<24 {
                group.addTask {
                    SemanticIndex.embed("Concurrent semantic embedding request \(index)")
                }
            }
            var results: [[Float]?] = []
            for await vector in group {
                results.append(vector)
            }
            return results
        }

        XCTAssertEqual(vectors.compactMap { $0 }.count, 24)
        XCTAssertEqual(Set(vectors.compactMap { $0?.count }).count, 1)
    }

    func testAppleIntelligenceAvailabilityProbeDoesNotBlockMainActor() async {
        let completed = expectation(description: "FoundationModels availability probe completed")
        Task { @MainActor in
            _ = await AppleIntelligenceService.availability()
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)
    }

    private func makeClipboardItem(
        id: UUID,
        createdAt: Date,
        textContent: String = "same preview",
        fingerprint: String = "same-fingerprint",
        pinnedTitle: String? = nil,
        rtfData: Data? = nil,
        imageData: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            createdAt: createdAt,
            type: .text,
            textContent: textContent,
            rtfData: rtfData,
            imageData: imageData,
            urlString: nil,
            fileURLs: [],
            sourceAppBundleId: "com.apple.Safari",
            sourceAppName: "Safari",
            isPinned: pinnedTitle != nil,
            pinnedTitle: pinnedTitle,
            typesData: [:],
            fingerprint: fingerprint
        )
    }

}
