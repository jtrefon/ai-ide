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
        let attributed = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        
        attributed.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        
        return attributed
    }
    
    open func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return []
    }
    
    open func format(_ code: String) -> String {
        return code // Default: no-op
    }
    
    // MARK: - Helper Methods
    
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
