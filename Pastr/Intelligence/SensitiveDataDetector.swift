import Foundation

/// Detects likely-sensitive content (secrets, cards, personal data) entirely on-device
/// using lightweight pattern matching. Used to optionally blur clips in the panel and to
/// exclude them from iCloud sync and backups.
enum SensitiveDataDetector {
    /// Classify how sensitive a string looks.
    static func sensitivity(of text: String?) -> SensitivityLevel {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .none
        }

        if looksLikeSecret(text) { return .high }
        if looksLikePersonal(text) { return .low }
        return .none
    }

    // MARK: - High sensitivity (secrets)

    private static func looksLikeSecret(_ text: String) -> Bool {
        // Private key blocks.
        if text.contains("BEGIN") && text.contains("PRIVATE KEY") { return true }

        // Common API-key / token formats. Keep these shape-based so short fragments like
        // "task-" do not trip the OpenAI/Stripe "sk-" prefix.
        if containsKnownSecretToken(text) {
            return true
        }

        // Credit-card-like numbers that pass a Luhn check.
        if let candidate = firstCardCandidate(in: text), passesLuhn(candidate) {
            return true
        }

        // High-entropy single token with no spaces.
        let firstToken = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? text
        if !text.contains(where: { $0.isWhitespace }),
           looksLikeStandaloneSecretToken(firstToken) {
            return true
        }

        // Explicit "password: ..." style assignments.
        if matches(text, pattern: #"(?i)\b(pass(word)?|secret|api[_-]?key|token)\b\s*[:=]\s*\S{6,}"#) {
            return true
        }

        return false
    }

    // MARK: - Low sensitivity (personal data)

    private static func looksLikePersonal(_ text: String) -> Bool {
        // Email address.
        if matches(text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, caseInsensitive: true) {
            return true
        }
        // Phone number (loose international form).
        if matches(text, pattern: #"(?:\+?\d[\d\s().-]{7,}\d)"#), text.count <= 40,
           text.filter(\.isNumber).count >= 7 {
            return true
        }
        // US-style SSN.
        if matches(text, pattern: #"\b\d{3}-\d{2}-\d{4}\b"#) {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private static func containsKnownSecretToken(_ text: String) -> Bool {
        let patterns = [
            #"\bsk-[A-Za-z0-9_-]{20,}\b"#,
            #"\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9_]{12,}\b"#,
            #"\b(?:ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,}\b"#,
            #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#,
            #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#,
            #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
            #"\bAIza[0-9A-Za-z_-]{20,}\b"#,
            #"\bya29\.[0-9A-Za-z_-]{20,}\b"#,
            #"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}\b"#,
            #"\bglpat-[A-Za-z0-9_-]{20,}\b"#,
            #"\bnpm_[A-Za-z0-9]{20,}\b"#
        ]

        return patterns.contains { matches(text, pattern: $0, caseInsensitive: true) }
    }

    private static func firstCardCandidate(in text: String) -> String? {
        // 13–19 digits, optionally separated by spaces or dashes.
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]?){13,19}\b"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r]).filter(\.isNumber)
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count >= 13 else { return false }
        var sum = 0
        for (index, digit) in nums.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// Rough high-entropy gate for standalone pasted tokens. This intentionally ignores
    /// UUIDs, hashes, and shorter mixed identifiers that show up frequently in screenshots.
    private static func looksLikeStandaloneSecretToken(_ token: String) -> Bool {
        guard token.count >= 40, token.count <= 512 else { return false }
        if matches(token, pattern: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, caseInsensitive: true) {
            return false
        }

        let hasLower = token.contains(where: { $0.isLowercase })
        let hasUpper = token.contains(where: { $0.isUppercase })
        let hasDigit = token.contains(where: { $0.isNumber })
        let hasSecretSymbol = token.contains { "_-./+=".contains($0) }
        let classes = [hasLower, hasUpper, hasDigit, hasSecretSymbol].filter { $0 }.count
        guard classes >= 3 else { return false }

        let digitRatio = Double(token.filter(\.isNumber).count) / Double(token.count)
        return digitRatio > 0.1 || hasSecretSymbol
    }

    private static func matches(_ text: String, pattern: String, caseInsensitive: Bool = false) -> Bool {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
