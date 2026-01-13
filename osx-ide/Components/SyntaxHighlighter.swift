//
//  SyntaxHighlighter.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//  Updated to provide robust, always-on fallback highlighting for multiple languages.
//

import Foundation
import AppKit

/// A centralized syntax highlighting service that provides robust highlighting for multiple programming languages.
/// 
/// The SyntaxHighlighter uses a modular approach with language-specific modules when available,
/// and falls back to built-in highlighting for common languages when modules are not registered.
/// 
/// ## Usage
/// ```swift
/// let highlighter = SyntaxHighlighter.shared
/// let attributedString = highlighter.highlight(code, language: "swift", font: font)
/// ```
///
/// ## Supported Languages
/// - Swift (built-in)
/// - JavaScript/TypeScript (built-in)
/// - Python (built-in)
/// - HTML (built-in)
/// - CSS (built-in)
/// - JSON (built-in)
/// - Custom languages via LanguageModuleManager
@MainActor
final class SyntaxHighlighter {
    /// Shared singleton instance for syntax highlighting
    static let shared = SyntaxHighlighter()
    private init() {}

    private let regexHelper = RegexLanguageModule(id: .unknown, fileExtensions: [])

    /// Highlights the given code with syntax highlighting for the specified language.
    ///
    /// - Parameters:
    ///   - code: The source code to highlight
    ///   - language: The programming language identifier (e.g., "swift", "javascript", "python")
    ///   - font: The font to use for the highlighted text
    /// - Returns: An NSAttributedString with syntax highlighting applied
    func highlight(
        _ code: String, 
        language: String = "text", 
        font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    ) -> NSAttributedString {
        let langStr = LanguageIdentifierNormalizer.normalize(language)

        #if DEBUG
        print("[Highlighter] highlight raw=\(language) normalized=\(langStr) len=\((code as NSString).length)")
        #endif
        
        // Try to use modular language support if enabled
        if let module = resolveModule(for: langStr) {
            #if DEBUG
            print("[Highlighter] using module id=\(module.id.rawValue) extensions=\(module.fileExtensions)")
            #endif
            return module.highlight(code, font: font)
        }

        let (attributed, _) = regexHelper.makeBaseAttributedString(code: code, font: font)

        // Built-in always-on fallback highlighting (when no module is registered/enabled)
        let fallbackLanguage = CodeLanguage(rawValue: langStr) ?? .unknown
        #if DEBUG
        print("[Highlighter] using fallback language=\(fallbackLanguage.rawValue)")
        #endif

        applyFallbackHighlighting(
            fallbackLanguage: fallbackLanguage,
            attributed: attributed,
            code: code
        )

        return attributed
    }
    
    /// Incremental highlighting that reuses previous results for better performance
    struct HighlightIncrementalRequest {
        let code: String
        let language: String
        let font: NSFont
        let previousResult: NSAttributedString?

        init(
            code: String,
            language: String = "text",
            font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            previousResult: NSAttributedString? = nil
        ) {
            self.code = code
            self.language = language
            self.font = font
            self.previousResult = previousResult
        }
    }

    func highlightIncremental(
        _ request: HighlightIncrementalRequest
    ) async -> NSAttributedString {
        // For now, fall back to regular highlighting
        // In a full implementation, this would analyze changes and only re-highlight affected parts
        return highlight(request.code, language: request.language, font: request.font)
    }

    private func resolveModule(for languageIdentifier: String) -> (any LanguageModule)? {
        LanguageModuleManager.shared.getModule(forExtension: languageIdentifier) ??
            LanguageModuleManager.shared.getModule(
                for: CodeLanguage(rawValue: languageIdentifier) ?? .unknown
            )
    }

    private func applyFallbackHighlighting(
        fallbackLanguage: CodeLanguage,
        attributed: NSMutableAttributedString,
        code: String
    ) {
        let handlers: [CodeLanguage: (NSMutableAttributedString, String) -> Void] = [
            .swift: { [weak self] attr, code in self?.applySwiftHighlighting(in: attr, code: code) },
            .javascript: { [weak self] attr, code in self?.applyJavaScriptHighlighting(in: attr, code: code) },
            .typescript: { [weak self] attr, code in self?.applyTypeScriptHighlighting(in: attr, code: code) },
            .python: { [weak self] attr, code in self?.applyPythonHighlighting(in: attr, code: code) },
            .html: { [weak self] attr, code in self?.applyHTMLHighlighting(in: attr, code: code) },
            .css: { [weak self] attr, code in self?.applyCSSHighlighting(in: attr, code: code) },
            .json: { [weak self] attr, code in self?.applyJSONHighlighting(in: attr, code: code) }
        ]

        handlers[fallbackLanguage]?(attributed, code)
    }

    private func applySwiftHighlighting(in attr: NSMutableAttributedString, code: String) {
        applyGenericHighlighting(in: attr, code: code)
        let keywords = [
            "class","struct","enum","protocol","extension","func","var","let","if","else","for","while","repeat","switch","case","default","break","continue","defer","do","catch","throw","throws","rethrows","try","in","where","return","as","is","nil","true","false","init","deinit","subscript","typealias","associatedtype","mutating","nonmutating","static","final","open","public","internal","fileprivate","private","guard","some","any","actor","await","async","yield","inout"
        ]
        let types = [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "Bool", "String", "Character",
            "Array", "Dictionary", "Set", "Optional", "Void", "Any", "AnyObject"
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
        let tsKeywords = [
                "interface","type","implements","namespace","abstract",
                "public","private","protected","readonly"
            ]
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
        DefaultCSSHighlighter.applyAll(in: attr, code: code)
    }

    private func applyJSONHighlighting(in attr: NSMutableAttributedString, code: String) {
        #if DEBUG
        print("[Highlighter] applyJSONHighlighting triggered")
        #endif
        let palette = (LanguageModuleManager.shared.getModule(for: .json) as? HighlightPaletteProviding)?.highlightPalette
        let defaultColors = JSONTokenHighlighter.DefaultColors(colors: [
            .key: NSColor.systemIndigo,
            .string: NSColor.systemRed,
            .number: NSColor.systemOrange,
            .boolean: NSColor.systemBlue,
            .null: NSColor.systemGray,
            .quote: NSColor.systemPink,
            .brace: NSColor.systemTeal,
            .bracket: NSColor.systemPurple,
            .comma: NSColor.systemBrown,
            .colon: NSColor.systemYellow
        ])

        let callbacks = JSONTokenHighlighter.Callbacks(
            applyRegex: { [weak self] pattern, color, captureGroup in
                self?.applyRegex(pattern, color: color, in: attr, code: code, captureGroup: captureGroup)
            },
            highlightWholeWords: { [weak self] words, color in
                self?.highlightWholeWords(words, color: color, in: attr, code: code)
            }
        )

        JSONTokenHighlighter.applyAll(
            in: attr,
            code: code,
            palette: palette,
            defaultColors: defaultColors,
            callbacks: callbacks
        )
    }

    private func applyGenericHighlighting(in attr: NSMutableAttributedString, code: String) {
        regexHelper.applyDoubleAndSingleQuotedStringHighlighting(color: NSColor.systemRed, in: attr, code: code)
        regexHelper.applyLineAndBlockCommentHighlighting(color: NSColor.systemGreen, in: attr, code: code)
        regexHelper.applyDecimalNumberHighlighting(color: NSColor.systemOrange, in: attr, code: code)
    }

    // MARK: - Helpers

    private func highlightWholeWords(
            _ words: [String], 
            color: NSColor, 
            in attr: NSMutableAttributedString, 
            code: String
        ) {
        regexHelper.highlightWholeWords(words, color: color, in: attr, code: code)
    }

    private func applyRegex(
        _ pattern: String,
        color: NSColor,
        in attr: NSMutableAttributedString,
        code: String,
        captureGroup: Int? = nil
    ) {
        let group = captureGroup
        regexHelper.applyRegex(pattern, color: color, in: attr, code: code, captureGroup: group)
    }
}
