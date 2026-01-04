//
//  SyntaxHighlighter.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//  Updated to provide robust, always-on fallback highlighting for multiple languages.
//

import Foundation
import AppKit

@MainActor
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    private init() {}

    // MARK: - Public API

    /// Returns an attributed string with syntax highlighting applied for the given language.
    /// This method uses a robust, always-on high-level highlighting approach.
    func highlight(_ code: String, language: String = "text", font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)) -> NSAttributedString {
        let langStr = normalizeLanguageIdentifier(language)

        #if DEBUG
        print("[Highlighter] highlight raw=\(language) normalized=\(langStr) len=\((code as NSString).length)")
        #endif
        
        // Try to use modular language support if enabled
        if let module = LanguageModuleManager.shared.getModule(forExtension: langStr) ??
            LanguageModuleManager.shared.getModule(for: CodeLanguage(rawValue: langStr) ?? .unknown) {
            #if DEBUG
            print("[Highlighter] using module id=\(module.id.rawValue) extensions=\(module.fileExtensions)")
            #endif
            return module.highlight(code, font: font)
        }

        let attributed = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)

        // Base style
        attributed.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        // Built-in always-on fallback highlighting (when no module is registered/enabled)
        let fallbackLanguage = CodeLanguage(rawValue: langStr) ?? .unknown
        #if DEBUG
        print("[Highlighter] using fallback language=\(fallbackLanguage.rawValue)")
        #endif

        switch fallbackLanguage {
        case .swift:
            applySwiftHighlighting(in: attributed, code: code)
        case .javascript:
            applyJavaScriptHighlighting(in: attributed, code: code)
        case .typescript:
            applyTypeScriptHighlighting(in: attributed, code: code)
        case .python:
            applyPythonHighlighting(in: attributed, code: code)
        case .html:
            applyHTMLHighlighting(in: attributed, code: code)
        case .css:
            applyCSSHighlighting(in: attributed, code: code)
        case .json:
            applyJSONHighlighting(in: attributed, code: code)
        default:
            break
        }

        return attributed
    }

    private func normalizeLanguageIdentifier(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Common forms:
        // - "LANGUAGE_SWIFT" -> "swift"
        // - "language_swift" -> "swift"
        // - ".swift" -> "swift"
        // - "swift" -> "swift"
        if s.hasPrefix("language_") {
            s.removeFirst("language_".count)
        }
        if s.hasPrefix(".") {
            s.removeFirst()
        }

        // Some callers may provide file extensions like "ts"/"js"; map common aliases.
        switch s {
        case "js":
            return "javascript"
        case "ts":
            return "typescript"
        case "py":
            return "python"
        default:
            return s
        }
    }

    // MARK: - Language Highlighting

    private func applySwiftHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyGenericHighlighting(in: attr, code: code)
        let keywords = [
            "class","struct","enum","protocol","extension","func","var","let","if","else","for","while","repeat","switch","case","default","break","continue","defer","do","catch","throw","throws","rethrows","try","in","where","return","as","is","nil","true","false","init","deinit","subscript","typealias","associatedtype","mutating","nonmutating","static","final","open","public","internal","fileprivate","private","guard","some","any","actor","await","async","yield","inout"
        ]
        let types = [
            "Int","Int8","Int16","Int32","Int64","UInt","UInt8","UInt16","UInt32","UInt64","Float","Double","Bool","String","Character","Array","Dictionary","Set","Optional","Void","Any","AnyObject"
        ]
        highlightWholeWords(keywords, color: NSColor.systemBlue, in: attr, code: code)
        highlightWholeWords(types, color: NSColor.systemPurple, in: attr, code: code)
    }

    private func applyJavaScriptHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyGenericHighlighting(in: attr, code: code)
        let keywords = [
            "break","case","catch","class","const","continue","debugger","default","delete","do","else","export","extends","finally","for","function","if","import","in","instanceof","let","new","return","super","switch","this","throw","try","typeof","var","void","while","with","yield","async","await"
        ]
        highlightWholeWords(keywords, color: NSColor.systemBlue, in: attr, code: code)
    }

    private func applyTypeScriptHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyJavaScriptHighlighting(in: attr, code: code)
        let tsKeywords = ["interface","type","implements","namespace","abstract","public","private","protected","readonly"]
        highlightWholeWords(tsKeywords, color: NSColor.systemPurple, in: attr, code: code)
    }

    private func applyPythonHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyGenericHighlighting(in: attr, code: code)
        let keywords = [
            "False","None","True","and","as","assert","async","await","break","class","continue","def","del","elif","else","except","finally","for","from","global","if","import","in","is","lambda","nonlocal","not","or","pass","raise","return","try","while","with","yield"
        ]
        highlightWholeWords(keywords, color: NSColor.systemBlue, in: attr, code: code)
        // Python comments (# ...)
        applyRegex("#.*", color: NSColor.systemGreen, in: attr, code: code)
        // Triple-quoted strings
        applyRegex("\"\"\"[\\s\\S]*?\"\"\"", color: NSColor.systemRed, in: attr, code: code)
        applyRegex("'''[\\s\\S]*?'''", color: NSColor.systemRed, in: attr, code: code)
    }

    private func applyHTMLHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyGenericHighlighting(in: attr, code: code)
        // Tags and tag names
        applyRegex("</?[a-zA-Z][a-zA-Z0-9:-]*", color: NSColor.systemBlue, in: attr, code: code)
        // Attributes
        applyRegex("[a-zA-Z_:][-a-zA-Z0-9_:.]*(?=\\=)", color: NSColor.systemPurple, in: attr, code: code)
        // Comments
        applyRegex("<!--[\\s\\S]*?-->", color: NSColor.systemGreen, in: attr, code: code)
    }

    private func applyCSSHighlighting(in attr: NSMutableAttributedString, code: String) {
        // Match the stronger CSS scheme used by CSSModule so fallback stays consistent.
        // 1. Selectors (Classes, IDs, Tags, Pseudo-elements)
        applyRegex("(?m)^[ \t]*:root\\b", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*@[-a-zA-Z]+", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*\\.[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*#[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*:{1,2}[a-zA-Z-]+\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)

        // 2. Braces / punctuation
        applyRegex("[\\{\\}\\[\\]\\(\\);:,]", color: NSColor.systemMint, in: attr, code: code)

        // 3. Property Keys (including custom properties: --foo)
        applyRegex("(?<=[\\{\\s;])(--[a-zA-Z0-9-]+|[a-zA-Z-][a-zA-Z0-9-]*)\\s*(?=:)", color: NSColor.systemBlue, in: attr, code: code, captureGroup: 1)

        // 4. Custom property references
        applyRegex("--[a-zA-Z0-9-]+", color: NSColor.systemBlue, in: attr, code: code)

        // 5. Functions
        applyRegex("\\b[a-zA-Z-]+\\s*(?=\\()", color: NSColor.systemBrown, in: attr, code: code)

        // 6. Hex colors
        applyRegex("#[0-9a-fA-F]{3,8}\\b", color: NSColor.systemOrange, in: attr, code: code)

        // 7. Numbers and Units
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(px|em|rem|%|vh|vw|s|ms|deg)?\\b", color: NSColor.systemYellow, in: attr, code: code)

        // 8. Quoted values (inside)
        applyRegex("\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\"", color: NSColor.systemCyan, in: attr, code: code, captureGroup: 1)
        applyRegex("'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'", color: NSColor.systemCyan, in: attr, code: code, captureGroup: 1)

        // 9. Quotes
        applyRegex("\"", color: NSColor.systemIndigo, in: attr, code: code)
        applyRegex("'", color: NSColor.systemBrown, in: attr, code: code)

        // 10. Bare identifiers in values
        applyRegex("(?<=:)\\s*([a-zA-Z_-][a-zA-Z0-9_-]*)\\b", color: NSColor.systemCyan, in: attr, code: code, captureGroup: 1)

        // 11. Comments
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.tertiaryLabelColor, in: attr, code: code)
    }

    private func applyJSONHighlighting(in attr: NSMutableAttributedString, code: String) {
        // Keys
        applyRegex("\"([^\"]+)\"\\s*:(?=\\s)", color: NSColor.systemPurple, in: attr, code: code, captureGroup: 1)
        // String values
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor.systemRed, in: attr, code: code)
        // Numbers
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", color: NSColor.systemOrange, in: attr, code: code)
        // Booleans and null
        highlightWholeWords(["true","false","null"], color: NSColor.systemBlue, in: attr, code: code)
    }

    private func applyGenericHighlighting(in attr: NSMutableAttributedString, code: String) {
        // Strings (double and single quoted)
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor.systemRed, in: attr, code: code)
        applyRegex("'(?:\\\\.|[^'\\\\])*'", color: NSColor.systemRed, in: attr, code: code)
        // Line comments //...
        applyRegex("//.*", color: NSColor.systemGreen, in: attr, code: code)
        // Block comments /* ... */
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.systemGreen, in: attr, code: code)
        // Numbers
        applyRegex("\\b\\d+(?:\\.\\d+)?\\b", color: NSColor.systemOrange, in: attr, code: code)
    }

    // MARK: - Helpers

    private func highlightWholeWords(_ words: [String], color: NSColor, in attr: NSMutableAttributedString, code: String) {
        guard !words.isEmpty else { return }
        // Build a regex like: \b(word1|word2|...)\b
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
        applyRegex(pattern, color: color, in: attr, code: code)
    }

    private func applyRegex(_ pattern: String, color: NSColor, in attr: NSMutableAttributedString, code: String, captureGroup: Int? = nil) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
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
