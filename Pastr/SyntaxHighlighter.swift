import AppKit
import SwiftUI

enum SyntaxHighlighter {
    // MARK: - Colors

    private static let keywordColor = NSColor(red: 0.78, green: 0.44, blue: 0.78, alpha: 1.0) // Purple
    private static let stringColor = NSColor(red: 0.89, green: 0.44, blue: 0.36, alpha: 1.0) // Orange/Red
    private static let commentColor = NSColor(red: 0.46, green: 0.53, blue: 0.60, alpha: 1.0) // Gray
    private static let numberColor = NSColor(red: 0.82, green: 0.68, blue: 0.38, alpha: 1.0) // Yellow
    private static let typeColor = NSColor(red: 0.35, green: 0.73, blue: 0.82, alpha: 1.0) // Cyan
    private static let functionColor = NSColor(red: 0.40, green: 0.72, blue: 0.40, alpha: 1.0) // Green
    private static let defaultColor = NSColor.white

    // MARK: - Cached Regex Patterns (avoid allocation on every call)

    private static let doubleQuoteStringRegex = try? NSRegularExpression(pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#)
    private static let singleQuoteStringRegex = try? NSRegularExpression(pattern: #"'[^'\\]*(?:\\.[^'\\]*)*'"#)
    private static let templateLiteralRegex = try? NSRegularExpression(pattern: #"`[^`]*`"#)
    private static let singleLineCommentRegex = try? NSRegularExpression(pattern: #"//.*$"#, options: .anchorsMatchLines)
    private static let multiLineCommentRegex = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)
    private static let hashCommentRegex = try? NSRegularExpression(pattern: #"#.*$"#, options: .anchorsMatchLines)
    private static let numberRegex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\b"#)
    private static let functionCallRegex = try? NSRegularExpression(pattern: #"\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#)

    // Pre-compiled keyword and type regexes
    private static let keywordRegexes: [NSRegularExpression] = keywords.compactMap {
        try? NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#)
    }
    private static let typeRegexes: [NSRegularExpression] = types.compactMap {
        try? NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#)
    }

    // MARK: - Result Cache (avoid re-highlighting same text)

    private static var highlightCache = NSCache<NSString, NSAttributedString>()
    private static var codeDetectionCache = NSCache<NSString, NSNumber>()

    // MARK: - Keywords

    private static let keywords: Set<String> = [
        // Swift
        "func", "var", "let", "class", "struct", "enum", "protocol", "extension",
        "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
        "return", "break", "continue", "throw", "throws", "try", "catch", "do",
        "import", "public", "private", "internal", "fileprivate", "open", "static",
        "final", "override", "mutating", "lazy", "weak", "unowned", "self", "super",
        "init", "deinit", "nil", "true", "false", "async", "await", "actor",
        // JavaScript/TypeScript
        "function", "const", "new", "this", "typeof", "instanceof", "delete",
        "export", "from", "async", "yield", "of", "in",
        // Python
        "def", "lambda", "with", "as", "from", "import", "pass", "raise", "except",
        "finally", "global", "nonlocal", "assert", "yield", "None", "True", "False",
        // General
        "void", "int", "float", "double", "bool", "string", "null", "undefined"
    ]

    private static let types: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "Any", "AnyObject", "Void", "Never",
        "CGFloat", "NSImage", "NSColor", "View", "ObservableObject", "Published",
        "State", "Binding", "EnvironmentObject", "StateObject"
    ]

    // MARK: - Code Indicators (pre-lowercased for faster comparison)

    private static let codeIndicators = [
        "func ", "class ", "struct ", "enum ", "let ", "var ",
        "function ", "const ", "def ", "import ", "from ",
        "public ", "private ", "static ", "return ",
        "if (", "if(", "for (", "for(", "while (",
        "=> ", "->", "::", "&&", "||",
        "();", ");", "};", "{}", "[]",
    ]

    // MARK: - Detection

    static func isLikelyCode(_ text: String) -> Bool {
        // Check cache first
        let cacheKey = text as NSString
        if let cached = codeDetectionCache.object(forKey: cacheKey) {
            return cached.boolValue
        }

        let lowercased = text.lowercased()
        var matchCount = 0
        for indicator in codeIndicators {
            if lowercased.contains(indicator.lowercased()) {
                matchCount += 1
                if matchCount >= 2 { break } // Early exit optimization
            }
        }

        // Also check for common patterns
        let hasIndentation = text.contains("\n    ") || text.contains("\n\t")
        let hasBraces = text.contains("{") && text.contains("}")
        let hasParens = text.contains("(") && text.contains(")")

        let result = matchCount >= 2 || (matchCount >= 1 && (hasIndentation || (hasBraces && hasParens)))

        // Cache the result
        codeDetectionCache.setObject(NSNumber(value: result), forKey: cacheKey)

        return result
    }

    // MARK: - Highlighting

    static func highlight(_ text: String) -> NSAttributedString {
        // Check cache first
        let cacheKey = text as NSString
        if let cached = highlightCache.object(forKey: cacheKey) {
            return cached
        }

        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)

        // Default styling
        attributed.addAttributes([
            .foregroundColor: defaultColor,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ], range: fullRange)

        // Use cached regexes for highlighting
        if let regex = doubleQuoteStringRegex {
            applyHighlight(regex: regex, in: attributed, with: stringColor)
        }
        if let regex = singleQuoteStringRegex {
            applyHighlight(regex: regex, in: attributed, with: stringColor)
        }
        if let regex = templateLiteralRegex {
            applyHighlight(regex: regex, in: attributed, with: stringColor)
        }
        if let regex = singleLineCommentRegex {
            applyHighlight(regex: regex, in: attributed, with: commentColor)
        }
        if let regex = multiLineCommentRegex {
            applyHighlight(regex: regex, in: attributed, with: commentColor)
        }
        if let regex = hashCommentRegex {
            applyHighlight(regex: regex, in: attributed, with: commentColor)
        }
        if let regex = numberRegex {
            applyHighlight(regex: regex, in: attributed, with: numberColor)
        }

        // Highlight keywords using pre-compiled regexes
        for regex in keywordRegexes {
            applyHighlight(regex: regex, in: attributed, with: keywordColor)
        }

        // Highlight types using pre-compiled regexes
        for regex in typeRegexes {
            applyHighlight(regex: regex, in: attributed, with: typeColor)
        }

        // Highlight function calls
        if let regex = functionCallRegex {
            applyHighlight(regex: regex, in: attributed, with: functionColor, captureGroup: 1)
        }

        // Cache the result
        highlightCache.setObject(attributed, forKey: cacheKey)

        return attributed
    }

    private static func applyHighlight(
        regex: NSRegularExpression,
        in attributed: NSMutableAttributedString,
        with color: NSColor,
        captureGroup: Int = 0
    ) {
        let string = attributed.string
        let range = NSRange(location: 0, length: string.utf16.count)

        regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = captureGroup == 0 ? match.range : match.range(at: captureGroup)
            if matchRange.location != NSNotFound {
                attributed.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }

    // MARK: - SwiftUI AttributedString

    static func highlightedAttributedString(_ text: String) -> AttributedString {
        let nsAttributed = highlight(text)
        return AttributedString(nsAttributed)
    }
}
