import Foundation
import NaturalLanguage

/// Classifies a clip into a coarse `ContentCategory` and suggests tag names, using
/// deterministic heuristics plus NaturalLanguage named-entity recognition. On-device,
/// macOS 14+.
enum ContentClassifier {
    struct Result {
        let category: ContentCategory
        let tagSuggestions: [String]
    }

    static func classify(_ item: ClipboardItem) -> Result {
        // Non-text clips are categorised structurally.
        switch item.type {
        case .image:
            return Result(category: .other, tagSuggestions: ["image"])
        case .file:
            return Result(category: .other, tagSuggestions: fileTagSuggestions(item))
        case .link:
            let host = item.urlString.flatMap { URL(string: $0)?.host }
            return Result(category: .url, tagSuggestions: ["link", host].compactMap { $0 })
        default:
            break
        }

        guard let text = item.plainText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return Result(category: .other, tagSuggestions: [])
        }

        let category = category(for: text)
        var suggestions: [String] = [category.label.lowercased()]
        suggestions.append(contentsOf: entityTags(in: text))
        return Result(category: category, tagSuggestions: dedupe(suggestions))
    }

    // MARK: - Category heuristics

    static func category(for text: String) -> ContentCategory {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isColor(trimmed) { return .color }
        if isJSON(trimmed) { return .json }
        if isURL(trimmed) { return .url }
        if isEmail(trimmed) { return .email }
        if isPhone(trimmed) { return .phone }
        if isNumber(trimmed) { return .number }
        if isCommand(trimmed) { return .command }
        if isCode(trimmed) { return .code }
        if isProse(trimmed) { return .prose }
        return .other
    }

    private static func isColor(_ t: String) -> Bool {
        regexFull(t, #"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})"#) ||
        regexFull(t, #"(?i)(rgb|rgba|hsl|hsla)\(\s*[\d.,%\s/]+\)"#)
    }

    private static func isJSON(_ t: String) -> Bool {
        guard (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        guard let data = t.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func isURL(_ t: String) -> Bool {
        guard !t.contains(where: { $0.isWhitespace }) else { return false }
        guard let url = URL(string: t), let scheme = url.scheme else { return false }
        return ["http", "https", "ftp"].contains(scheme.lowercased()) && url.host != nil
    }

    private static func isEmail(_ t: String) -> Bool {
        regexFull(t, #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, caseInsensitive: true)
    }

    private static func isPhone(_ t: String) -> Bool {
        guard t.count <= 24, t.filter(\.isNumber).count >= 7 else { return false }
        return regexFull(t, #"\+?[\d\s().-]{7,}"#)
    }

    private static func isNumber(_ t: String) -> Bool {
        regexFull(t, #"[-+]?\d[\d,]*(\.\d+)?%?"#)
    }

    private static func isCommand(_ t: String) -> Bool {
        guard !t.contains("\n") else {
            // Multi-line: treat as command only if the first line starts with a shell verb.
            guard let first = t.split(separator: "\n").first.map(String.init) else { return false }
            return startsWithShellVerb(first)
        }
        return startsWithShellVerb(t)
    }

    private static func startsWithShellVerb(_ line: String) -> Bool {
        let verbs = ["sudo", "git", "npm", "yarn", "pnpm", "brew", "cd", "ls", "cat", "curl",
                     "docker", "kubectl", "ssh", "scp", "python", "pip", "node", "swift",
                     "xcodebuild", "make", "rm", "mkdir", "echo", "grep", "find", "open", "./"]
        let firstWord = line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        return verbs.contains(firstWord) || firstWord.hasPrefix("./")
    }

    private static func isCode(_ t: String) -> Bool {
        let codeSignals = [";", "{", "}", "()", "=>", "==", "->", "::", "</", "/>", "def ",
                           "func ", "class ", "import ", "const ", "let ", "var ", "return ",
                           "public ", "private ", "#include", "<?php"]
        let hits = codeSignals.filter { t.contains($0) }.count
        // Multiple structural signals, or clearly indented multi-line content.
        if hits >= 2 { return true }
        if t.contains("\n") {
            let indented = t.split(separator: "\n").filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if indented >= 2 && hits >= 1 { return true }
        }
        return false
    }

    private static func isProse(_ t: String) -> Bool {
        // A few words, mostly letters, ending sensibly — looks like natural language.
        let words = t.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3 else { return false }
        let letters = t.filter { $0.isLetter || $0.isWhitespace }.count
        return Double(letters) / Double(max(t.count, 1)) > 0.7
    }

    // MARK: - Entity tags (NER)

    private static func entityTags(in text: String) -> [String] {
        // Cap work for very large clips.
        let sample = String(text.prefix(2000))
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sample

        var tags: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: sample.startIndex..<sample.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: options) { tag, range in
            if let tag {
                switch tag {
                case .personalName: tags.append("person")
                case .placeName: tags.append("place")
                case .organizationName:
                    tags.append(String(sample[range]).lowercased())
                default: break
                }
            }
            return tags.count < 6
        }
        return tags
    }

    // MARK: - File suggestions

    private static func fileTagSuggestions(_ item: ClipboardItem) -> [String] {
        var tags = ["file"]
        let exts = Set(item.fileURLs.map { $0.pathExtension.lowercased() }.filter { !$0.isEmpty })
        tags.append(contentsOf: exts)
        return Array(tags.prefix(4))
    }

    // MARK: - Utilities

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for v in values {
            let key = v.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(v)
        }
        return Array(result.prefix(6))
    }

    private static func regexFull(_ text: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
        var opts: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        // "Full" means the match covers essentially the whole trimmed string.
        return match.range.length >= range.length - 1
    }
}
