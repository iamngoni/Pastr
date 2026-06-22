import Foundation

/// A "Paste as…" transformation applied to a clip's text by Apple Intelligence (Tier 2).
/// Each case carries the model instructions and a user-facing label.
enum TextTransform: String, CaseIterable, Identifiable {
    case cleanUp
    case professional
    case friendly
    case concise
    case bulletPoints
    case markdown
    case json
    case extractActions
    case translateToEnglish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cleanUp: return "Clean Up & Fix Grammar"
        case .professional: return "Rewrite Professionally"
        case .friendly: return "Rewrite Friendlier"
        case .concise: return "Make Concise"
        case .bulletPoints: return "Turn Into Bullet Points"
        case .markdown: return "Format as Markdown"
        case .json: return "Convert to JSON"
        case .extractActions: return "Extract Action Items"
        case .translateToEnglish: return "Translate to English"
        }
    }

    var systemImage: String {
        switch self {
        case .cleanUp: return "wand.and.sparkles"
        case .professional: return "briefcase"
        case .friendly: return "face.smiling"
        case .concise: return "scissors"
        case .bulletPoints: return "list.bullet"
        case .markdown: return "number"
        case .json: return "curlybraces"
        case .extractActions: return "checklist"
        case .translateToEnglish: return "globe"
        }
    }

    /// Instructions handed to the language-model session.
    var instructions: String {
        switch self {
        case .cleanUp:
            return "You fix spelling, grammar, and punctuation in text while preserving its original meaning, tone, and formatting. Output only the corrected text."
        case .professional:
            return "You rewrite text in a clear, professional tone suitable for business communication. Preserve all facts. Output only the rewritten text."
        case .friendly:
            return "You rewrite text in a warm, friendly, approachable tone. Preserve all facts. Output only the rewritten text."
        case .concise:
            return "You rewrite text to be as concise as possible without losing meaning. Output only the shortened text."
        case .bulletPoints:
            return "You convert text into a clean bulleted list, one idea per bullet using the '- ' prefix. Output only the list."
        case .markdown:
            return "You reformat text as well-structured Markdown using headings, lists, and emphasis where appropriate. Output only the Markdown."
        case .json:
            return "You convert the provided text into a single valid JSON value that best represents its structure. Output only the JSON, with no code fences or commentary."
        case .extractActions:
            return "You extract concrete action items or tasks from text as a Markdown checklist using '- [ ] '. If there are none, output 'No action items found.' Output only the checklist."
        case .translateToEnglish:
            return "You translate text into natural English. If it is already English, return it unchanged. Output only the translation."
        }
    }

    /// Whether the transform output should overwrite or be offered as a paste-able result.
    var prompt: String { "Transform the following text accordingly:" }
}
