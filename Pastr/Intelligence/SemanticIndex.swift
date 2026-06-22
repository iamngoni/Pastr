import Foundation
import NaturalLanguage

/// Computes sentence embeddings for clips and ranks them against a query using cosine
/// similarity, enabling "search by meaning". On-device (NaturalLanguage), macOS 14+.
enum SemanticIndex {
    /// Minimum cosine similarity for a clip to be considered a semantic match.
    static let matchThreshold: Float = 0.30

    /// Shared English sentence-embedding model. Loaded lazily; may be `nil` if the model
    /// asset isn't available on the system.
    private static let model: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    static var isAvailable: Bool { model != nil }

    /// Embed a clip's representative text. Returns `nil` for clips with no usable text.
    static func embed(_ text: String?) -> [Float]? {
        guard let model,
              let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        // Sentence embeddings are tuned for short text; cap to keep them representative.
        let sample = String(text.prefix(500))
        guard let vector = model.vector(for: sample) else { return nil }
        return vector.map { Float($0) }
    }

    /// Embed an arbitrary query string (same space as `embed`).
    static func embedQuery(_ query: String) -> [Float]? {
        embed(query)
    }

    /// Cosine similarity between two equal-length vectors. Returns 0 for mismatched or empty.
    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = (normA.squareRoot() * normB.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }
}
