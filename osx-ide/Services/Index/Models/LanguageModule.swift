//
//  LanguageModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

// Explicitly import required types if they are not being resolved automatically
// CodeLanguage and Symbol are defined in Services/Index/Models/IndexModels.swift

public struct AnySymbolExtractor: Sendable {
    private let _extract: @Sendable (_ content: String, _ resourceId: String) -> [Symbol]

    public init(_ extract: @Sendable @escaping (_ content: String, _ resourceId: String) -> [Symbol]) {
        self._extract = extract
    }

    public func extractSymbols(content: String, resourceId: String) -> [Symbol] {
        _extract(content, resourceId)
    }
}

public enum LanguageIdentifierNormalizer {
    public static func normalize(_ raw: String) -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasPrefix("language_") {
            normalized.removeFirst("language_".count)
        }
        if normalized.hasPrefix(".") {
            normalized.removeFirst()
        }

        switch normalized {
        case "js":
            return "javascript"
        case "ts":
            return "typescript"
        case "py":
            return "python"
        default:
            return normalized
        }
    }
}

/// Defines the capabilities a language-specific module must provide.
public protocol LanguageModule: Sendable {
    /// Unique identifier for the language.
    var id: CodeLanguage { get }
    
    /// File extensions supported by this module.
    var fileExtensions: [String] { get }
    
    /// Applies syntax highlighting to the provided code string.
    func highlight(_ code: String, font: NSFont) -> NSAttributedString
    
    /// Parses symbols from the provided content for indexing.
    func parseSymbols(content: String, resourceId: String) -> [Symbol]
    
    /// Formats the provided code according to language standards.
    func format(_ code: String) -> String
}

public extension LanguageModule {
    var symbolExtractor: AnySymbolExtractor {
        AnySymbolExtractor { content, resourceId in
            parseSymbols(content: content, resourceId: resourceId)
        }
    }
}

/// Base class for regex-based language modules to reduce boilerplate.
open class RegexLanguageModule: LanguageModule, @unchecked Sendable {
    public let id: CodeLanguage
    public let fileExtensions: [String]
    
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
        return code // Default: no-op
    }
    
    // MARK: - Helper Methods

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
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: color, in: attr, code: code)
        applyRegex("'(?:\\\\.|[^'\\\\])*'", color: color, in: attr, code: code)
    }

    public func applyDoubleQuotedStringHighlighting(
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String
    ) {
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: color, in: attr, code: code)
    }

    public func applyLineAndBlockCommentHighlighting(
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String
    ) {
        applyRegex("//.*", color: color, in: attr, code: code)
        applyRegex("/\\*[\\s\\S]*?\\*/", color: color, in: attr, code: code)
    }

    public func applyDecimalNumberHighlighting(color: NSColor, in attr: NSMutableAttributedString, code: String) {
        applyRegex("\\b\\d+(?:\\.\\d+)?\\b", color: color, in: attr, code: code)
    }
    
    public func highlightWholeWords(_ words: [String], color: NSColor, in attr: NSMutableAttributedString, code: String) {
        guard !words.isEmpty else { return }
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
        applyRegex(pattern, color: color, in: attr, code: code)
    }
    
    public func applyRegex(
            _ pattern: String, 
            color: NSColor, 
            in attr: NSMutableAttributedString, 
            code: String, 
            captureGroup: Int? = nil
        ) {
        guard let regex = try? NSRegularExpression(
                    pattern: pattern, 
                    options: [.dotMatchesLineSeparators]
                ) else { return }
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
            "(?<=[\\{\\s;])(--[a-zA-Z0-9-]+|[a-zA-Z-][a-zA-Z0-9-]*)\\s*(?=:)",
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
