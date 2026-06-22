import Foundation
import FoundationModels

/// Availability of Apple Intelligence on this machine, expressed without an `@available`
/// gate so the rest of the app (deployment target macOS 14) can reason about it.
enum AppleIntelligenceAvailability: Equatable {
    case available
    /// OS is older than macOS 26 — the framework isn't present at all.
    case unsupportedOS
    /// Hardware can't run Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence is turned off in System Settings.
    case notEnabled
    /// Model assets are still downloading / warming up.
    case modelNotReady
    case unknown

    var isAvailable: Bool { self == .available }

    var message: String {
        switch self {
        case .available: return "Apple Intelligence is ready."
        case .unsupportedOS: return "Requires macOS 26 or later."
        case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
        case .notEnabled: return "Turn on Apple Intelligence in System Settings."
        case .modelNotReady: return "Apple Intelligence is getting ready. Try again shortly."
        case .unknown: return "Apple Intelligence is unavailable."
        }
    }
}

enum AppleIntelligenceError: LocalizedError {
    case unavailable(AppleIntelligenceAvailability)
    case emptyInput
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let a): return a.message
        case .emptyInput: return "There's no text to work with."
        case .emptyResponse: return "Apple Intelligence didn't return anything."
        }
    }
}

/// Thin wrapper over the on-device `FoundationModels` language model (Tier 2). Every entry
/// point is safe to call on macOS 14+: the work is gated to macOS 26 and throws a typed
/// error when unavailable, so callers can fall back to Tier 1 behaviour.
enum AppleIntelligenceService {
    /// Upper bound on characters fed to the model to keep latency and context in check.
    private static let maxInputCharacters = 6000

    static var availability: AppleIntelligenceAvailability {
        guard #available(macOS 26.0, *) else { return .unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown
            }
        @unknown default:
            return .unknown
        }
    }

    static var isAvailable: Bool { availability.isAvailable }

    /// Generate a short (≤ 5 word) title for a clip.
    static func generateTitle(for text: String) async throws -> String {
        let input = try prepared(text)
        let instructions = "You write very short titles. Given some text, respond with a concise title of at most five words that captures its essence. Output only the title, with no quotes or punctuation at the end."
        return try await respond(instructions: instructions, prompt: "Title this text:\n\n\(input)")
    }

    /// Summarise a clip into a sentence or two.
    static func summarize(_ text: String) async throws -> String {
        let input = try prepared(text)
        let instructions = "You summarise text. Respond with a clear summary of at most two sentences. Output only the summary."
        return try await respond(instructions: instructions, prompt: "Summarise this text:\n\n\(input)")
    }

    /// Apply a "Paste as…" transform to a clip's text.
    static func transform(_ text: String, _ transform: TextTransform) async throws -> String {
        let input = try prepared(text)
        return try await respond(instructions: transform.instructions,
                                 prompt: "\(transform.prompt)\n\n\(input)")
    }

    // MARK: - Core

    private static func prepared(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppleIntelligenceError.emptyInput }
        return String(trimmed.prefix(maxInputCharacters))
    }

    private static func respond(instructions: String, prompt: String) async throws -> String {
        let current = availability
        guard current.isAvailable else { throw AppleIntelligenceError.unavailable(current) }
        guard #available(macOS 26.0, *) else { throw AppleIntelligenceError.unavailable(.unsupportedOS) }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AppleIntelligenceError.emptyResponse }
        return content
    }
}
