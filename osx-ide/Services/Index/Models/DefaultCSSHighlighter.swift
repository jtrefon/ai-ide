import AppKit
import Foundation

public enum DefaultCSSHighlighter {
    public static func applyAll(in attr: NSMutableAttributedString, code: String) {
        applySelectorHighlighting(in: attr, code: code)
        applyPunctuationHighlighting(in: attr, code: code)
        applyPropertyHighlighting(in: attr, code: code)
        applyLiteralHighlighting(in: attr, code: code)
        applyCommentHighlighting(in: attr, code: code)
    }

    public static func applySelectorHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyRegex("(?m)^[ \t]*:root\\b", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*@[-a-zA-Z]+", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex(
            "(?m)^[ \t]*[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])",
            color: NSColor.systemGreen,
            in: attr,
            code: code
        )
        applyRegex(
            "(?m)^[ \t]*\\.[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])",
            color: NSColor.systemGreen,
            in: attr,
            code: code
        )
        applyRegex(
            "(?m)^[ \t]*#[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])",
            color: NSColor.systemGreen,
            in: attr,
            code: code
        )
        applyRegex(
            "(?m)^[ \t]*:{1,2}[a-zA-Z-]+\\s*(?=[,{])",
            color: NSColor.systemGreen,
            in: attr,
            code: code
        )
    }

    public static func applyPunctuationHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyRegex("[\\{\\}\\[\\]\\(\\);:,]", color: NSColor.systemMint, in: attr, code: code)
    }

    public static func applyPropertyHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyRegex(
            "(?<=[\\{\\s;])(--[a-zA-Z0-9-]+|[a-zA-Z-][a-zA-Z0-9-]*)\\s*(?=:)" ,
            color: NSColor.systemBlue,
            in: attr,
            code: code,
            captureGroup: 1
        )
        applyRegex("--[a-zA-Z0-9-]+", color: NSColor.systemBlue, in: attr, code: code)
        applyRegex("\\b[a-zA-Z-]+\\s*(?=\\()", color: NSColor.systemBrown, in: attr, code: code)
    }

    public static func applyLiteralHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyRegex("#[0-9a-fA-F]{3,8}\\b", color: NSColor.systemOrange, in: attr, code: code)
        applyRegex(
            "\\b-?\\d+(?:\\.\\d+)?(px|em|rem|%|vh|vw|s|ms|deg)?\\b",
            color: NSColor.systemYellow,
            in: attr,
            code: code
        )
        applyRegex(
            "\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\"",
            color: NSColor.systemCyan,
            in: attr,
            code: code,
            captureGroup: 1
        )
        applyRegex(
            "'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'",
            color: NSColor.systemCyan,
            in: attr,
            code: code,
            captureGroup: 1
        )
        applyRegex("\"", color: NSColor.systemIndigo, in: attr, code: code)
        applyRegex("'", color: NSColor.systemBrown, in: attr, code: code)
        applyRegex(
            "(?<=:)\\s*([a-zA-Z_-][a-zA-Z0-9_-]*)\\b",
            color: NSColor.systemCyan,
            in: attr,
            code: code,
            captureGroup: 1
        )
    }

    public static func applyCommentHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.tertiaryLabelColor, in: attr, code: code)
    }

    private static func applyRegex(
        _ pattern: String,
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String,
        captureGroup: Int? = nil
    ) {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return
        }

        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: code, options: [], range: fullRange)
        for match in matches {
            let range = captureGroup != nil ? match.range(at: captureGroup!) : match.range
            if range.location != NSNotFound && range.length > 0 {
                attr.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }
}
