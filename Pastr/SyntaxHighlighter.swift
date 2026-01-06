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

    // MARK: - Detection

    static func isLikelyCode(_ text: String) -> Bool {
        let codeIndicators = [
            "func ", "class ", "struct ", "enum ", "let ", "var ",
            "function ", "const ", "def ", "import ", "from ",
            "public ", "private ", "static ", "return ",
            "if (", "if(", "for (", "for(", "while (",
            "=> ", "->", "::", "&&", "||",
            "();", ");", "};", "{}", "[]",
        ]

        let lowercased = text.lowercased()
        let matchCount = codeIndicators.filter { lowercased.contains($0.lowercased()) }.count

        // Also check for common patterns
        let hasIndentation = text.contains("\n    ") || text.contains("\n\t")
        let hasBraces = text.contains("{") && text.contains("}")
        let hasParens = text.contains("(") && text.contains(")")

        return matchCount >= 2 || (matchCount >= 1 && (hasIndentation || (hasBraces && hasParens)))
    }

    // MARK: - Highlighting

    static func highlight(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)

        // Default styling
        attributed.addAttributes([
            .foregroundColor: defaultColor,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ], range: fullRange)

        // Highlight strings (double quotes)
        highlightPattern(#""[^"\\]*(?:\\.[^"\\]*)*""#, in: attributed, with: stringColor)

        // Highlight strings (single quotes)
        highlightPattern(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, in: attributed, with: stringColor)

        // Highlight template literals
        highlightPattern(#"`[^`]*`"#, in: attributed, with: stringColor)

        // Highlight single-line comments
        highlightPattern(#"//.*$"#, in: attributed, with: commentColor, options: .anchorsMatchLines)

        // Highlight multi-line comments
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: attributed, with: commentColor)

        // Highlight hash comments (Python, Ruby, etc.)
        highlightPattern(#"#.*$"#, in: attributed, with: commentColor, options: .anchorsMatchLines)

        // Highlight numbers
        highlightPattern(#"\b\d+\.?\d*\b"#, in: attributed, with: numberColor)

        // Highlight keywords
        for keyword in keywords {
            highlightPattern(#"\b"# + NSRegularExpression.escapedPattern(for: keyword) + #"\b"#,
                           in: attributed, with: keywordColor)
        }

        // Highlight types (capitalized words that are known types)
        for type in types {
            highlightPattern(#"\b"# + NSRegularExpression.escapedPattern(for: type) + #"\b"#,
                           in: attributed, with: typeColor)
        }

        // Highlight function calls
        highlightPattern(#"\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#, in: attributed, with: functionColor, captureGroup: 1)

        return attributed
    }

    private static func highlightPattern(
        _ pattern: String,
        in attributed: NSMutableAttributedString,
        with color: NSColor,
        options: NSRegularExpression.Options = [],
        captureGroup: Int = 0
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }

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
