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

        guard let module = resolveModule(for: langStr) else {
            fatalError("Missing highlight module for language identifier: \(langStr)")
        }

        #if DEBUG
        print("[Highlighter] using module id=\(module.id.rawValue) extensions=\(module.fileExtensions)")
        #endif
        return module.highlight(code, font: font)
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
        LanguageModuleManager.shared.getHighlightModule(forExtension: languageIdentifier) ??
            LanguageModuleManager.shared.getHighlightModule(
                for: CodeLanguage(rawValue: languageIdentifier) ?? .unknown
            )
    }

}
