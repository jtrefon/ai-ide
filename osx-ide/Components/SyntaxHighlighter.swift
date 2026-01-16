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

    private lazy var fallbackModules: [CodeLanguage: any LanguageModule] = [
        .swift: SwiftModule(),
        .javascript: JavaScriptModule(),
        .typescript: TypeScriptModule(),
        .python: PythonModule(),
        .html: HTMLModule(),
        .css: CSSModule(),
        .json: JSONModule()
    ]

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
            code: code,
            font: font
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
        code: String,
        font: NSFont
    ) {
        let handlers: [CodeLanguage: (NSMutableAttributedString, String) -> Void] = [
            .swift: { [weak self] attr, code in self?.applySwiftHighlighting(in: attr, code: code, font: font) },
            .javascript: { [weak self] attr, code in self?.applyJavaScriptHighlighting(in: attr, code: code, font: font) },
            .typescript: { [weak self] attr, code in self?.applyTypeScriptHighlighting(in: attr, code: code, font: font) },
            .python: { [weak self] attr, code in self?.applyPythonHighlighting(in: attr, code: code, font: font) },
            .html: { [weak self] attr, code in self?.applyHTMLHighlighting(in: attr, code: code, font: font) },
            .css: { [weak self] attr, code in self?.applyCSSHighlighting(in: attr, code: code, font: font) },
            .json: { [weak self] attr, code in self?.applyJSONHighlighting(in: attr, code: code, font: font) }
        ]

        handlers[fallbackLanguage]?(attributed, code)
    }

    private func applyModuleHighlighting(
        language: CodeLanguage,
        in attr: NSMutableAttributedString,
        code: String,
        font: NSFont
    ) {
        guard let module = fallbackModules[language] else { return }
        let highlighted = module.highlight(code, font: font)
        attr.setAttributedString(highlighted)
    }

    private func applySwiftHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        applyModuleHighlighting(language: .swift, in: attr, code: code, font: font)
    }

    private func applyJavaScriptHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        applyModuleHighlighting(language: .javascript, in: attr, code: code, font: font)
    }

    private func applyTypeScriptHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        applyModuleHighlighting(language: .typescript, in: attr, code: code, font: font)
    }

    private func applyPythonHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        applyModuleHighlighting(language: .python, in: attr, code: code, font: font)
    }

    private func applyHTMLHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        applyModuleHighlighting(language: .html, in: attr, code: code, font: font)
    }

    private func applyCSSHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        // Match the stronger CSS scheme used by CSSModule so fallback stays consistent.
        applyModuleHighlighting(language: .css, in: attr, code: code, font: font)
    }

    private func applyJSONHighlighting(in attr: NSMutableAttributedString, code: String, font: NSFont) {
        #if DEBUG
        print("[Highlighter] applyJSONHighlighting triggered")
        #endif
        applyModuleHighlighting(language: .json, in: attr, code: code, font: font)
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
        let context = RegexLanguageModule.RegexHighlightContext(attributedString: attr, code: code)
        regexHelper.applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: pattern,
            color: color,
            context: context,
            captureGroup: captureGroup
        ))
    }
}
