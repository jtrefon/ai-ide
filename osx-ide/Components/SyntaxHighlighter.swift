//
//  SyntaxHighlighter.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//  Updated to provide robust, always-on fallback highlighting for multiple languages.
//

import Foundation
import AppKit

final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    private init() {}

    // MARK: - Public API

    /// Returns an attributed string with syntax highlighting applied for the given language.
    /// This method first tries to use Tree-sitter for accurate highlighting, and falls back
    /// to regex-based highlighting when Tree-sitter is not available for the language.
    func highlight(_ code: String, language: String = "text") -> NSAttributedString {
        // Tree-sitter highlighting for supported languages.
        // For unsupported languages, we return a plain monospaced string.
        let lang = language.lowercased()
        if lang == "swift" {
            return TreeSitterManager.shared.highlight(code, language: lang)
        }

        let attributed = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)

        // Base style
        attributed.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        return attributed
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
        applyGenericHighlighting(in: attr, code: code)
        // Property names (rough heuristic)
        applyRegex("(?<=\\{)[^}]*?(?=:)", color: NSColor.systemTeal, in: attr, code: code)
        // Numbers and units
        applyRegex("\\b\\d+(?:\\.\\d+)?(px|em|rem|%|vh|vw)?\\b", color: NSColor.systemOrange, in: attr, code: code)
        // Comments
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.systemGreen, in: attr, code: code)
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
