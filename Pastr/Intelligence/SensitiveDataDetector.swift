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

        // Common API-key / token prefixes (Stripe, GitHub, OpenAI, AWS, Slack, Google).
        let secretPrefixes = [
            "sk-", "sk_live_", "sk_test_", "pk_live_", "rk_live_",
            "ghp_", "gho_", "ghu_", "ghs_", "github_pat_",
            "xox", "AKIA", "ASIA", "AIza", "ya29.",
            "Bearer ", "glpat-", "npm_",
        ]
        for prefix in secretPrefixes where text.contains(prefix) {
            return true
        }

        // Credit-card-like numbers that pass a Luhn check.
        if let candidate = firstCardCandidate(in: text), passesLuhn(candidate) {
            return true
        }

        // High-entropy single token (e.g. a 32+ char hex/base64 secret) with no spaces.
        let firstToken = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? text
        if !text.contains(where: { $0.isWhitespace }),
           firstToken.count >= 32,
           isHighEntropyToken(firstToken) {
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

    /// Rough Shannon-entropy gate: high-entropy tokens mix character classes and don't look
    /// like ordinary words.
    private static func isHighEntropyToken(_ token: String) -> Bool {
        let hasLower = token.contains(where: { $0.isLowercase })
        let hasUpper = token.contains(where: { $0.isUppercase })
        let hasDigit = token.contains(where: { $0.isNumber })
        let classes = [hasLower, hasUpper, hasDigit].filter { $0 }.count
        // Require at least two character classes and an alphabet that isn't all letters.
        guard classes >= 2 else { return false }
        let digitRatio = Double(token.filter(\.isNumber).count) / Double(token.count)
        return digitRatio > 0.1 || classes >= 3
    }

    private static func matches(_ text: String, pattern: String, caseInsensitive: Bool = false) -> Bool {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
