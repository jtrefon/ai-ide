import AppKit
import Foundation

open class RegexLanguageModule: LanguageModule, @unchecked Sendable {
    public let id: CodeLanguage
    public let fileExtensions: [String]

    public struct RegexHighlightContext {
        public let attributedString: NSMutableAttributedString
        public let code: String
    }

    public struct RegexHighlightRequest {
        public let pattern: String
        public let color: NSColor
        public let context: RegexHighlightContext
        public let captureGroup: Int?
    }

    public init(id: CodeLanguage, fileExtensions: [String]) {
        self.id = id
        self.fileExtensions = fileExtensions
    }

    open func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let (attributed, _) = AttributedStringStyler.makeBaseAttributedString(code: code, font: font)
        return attributed
    }

    open func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return []
    }

    open func format(_ code: String) -> String {
        return code
    }

    public func makeBaseAttributedString(
        code: String,
        font: NSFont,
        textColor: NSColor = NSColor.labelColor
    ) -> (attributed: NSMutableAttributedString, fullRange: NSRange) {
        AttributedStringStyler.makeBaseAttributedString(code: code, font: font, textColor: textColor)
    }

    public func applyDoubleAndSingleQuotedStringHighlighting(
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String
    ) {
        let context = RegexHighlightContext(attributedString: attr, code: code)
        applyRegex(RegexHighlightRequest(pattern: "\"(?:\\\\.|[^\"\\\\])*\"", color: color, context: context, captureGroup: nil))
        applyRegex(RegexHighlightRequest(pattern: "'(?:\\\\.|[^'\\\\])*'", color: color, context: context, captureGroup: nil))
    }

    public func applyDoubleQuotedStringHighlighting(
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String
    ) {
        let context = RegexHighlightContext(attributedString: attr, code: code)
        applyRegex(RegexHighlightRequest(pattern: "\"(?:\\\\.|[^\"\\\\])*\"", color: color, context: context, captureGroup: nil))
    }

    public func applyLineAndBlockCommentHighlighting(
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String
    ) {
        let context = RegexHighlightContext(attributedString: attr, code: code)
        applyRegex(RegexHighlightRequest(pattern: "//.*", color: color, context: context, captureGroup: nil))
        applyRegex(RegexHighlightRequest(pattern: "/\\*[\\s\\S]*?\\*/", color: color, context: context, captureGroup: nil))
    }

    public func applyDecimalNumberHighlighting(color: NSColor, in attr: NSMutableAttributedString, code: String) {
        let context = RegexHighlightContext(attributedString: attr, code: code)
        applyRegex(RegexHighlightRequest(pattern: "\\b\\d+(?:\\.\\d+)?\\b", color: color, context: context, captureGroup: nil))
    }

    public func highlightWholeWords(_ words: [String], color: NSColor, in attr: NSMutableAttributedString, code: String) {
        guard !words.isEmpty else { return }
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
        let context = RegexHighlightContext(attributedString: attr, code: code)
        applyRegex(RegexHighlightRequest(pattern: pattern, color: color, context: context, captureGroup: nil))
    }

    public func applyRegex(_ request: RegexHighlightRequest) {
        guard let regex = try? NSRegularExpression(
            pattern: request.pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return }
        let ns = request.context.code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: request.context.code, options: [], range: fullRange)
        for match in matches {
            let range = request.captureGroup.map { match.range(at: $0) } ?? match.range
            if range.location != NSNotFound && range.length > 0 {
                request.context.attributedString.addAttribute(.foregroundColor, value: request.color, range: range)
            }
        }
    }
}
