import Foundation
import SwiftUI
#if canImport(SwiftTreeSitter)
import SwiftTreeSitter
#endif
import AppKit

#if canImport(TreeSitterSwift)
import TreeSitterSwift
#endif

// Forward declaration of the C function from the grammar if not automatically imported
// Removed, as tree_sitter_swift is already imported from TreeSitterSwift

final class TreeSitterManager {
    static let shared = TreeSitterManager()

    #if canImport(SwiftTreeSitter)
    private var parsers: [String: Parser] = [:]
    private var languageConfigurations: [String: LanguageConfiguration] = [:]
    private var highlightQueries: [String: Query] = [:]
    #endif

    private init() {
    }

    func highlight(_ code: String, language: String) -> NSAttributedString {
        // Base style to ensure we always compile and display something
        let attributed = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: (code as NSString).length)
        attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: full)
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        #if canImport(SwiftTreeSitter)
        guard let parser = parser(for: language) else {
            return attributed
        }

        let query: Query?
        if let config = languageConfiguration(for: language), let configQuery = config.queries[.highlights] {
            query = configQuery
        } else {
            query = highlightQuery(for: language)
        }

        guard let query else {
            return attributed
        }
        
        guard let tree = parser.parse(code) else {
            return attributed
        }

        // NOTE: This follows the official docs flow:
        // query.execute(in: tree) -> resolve(with: ...) -> highlights()
        let cursor = query.execute(in: tree)
        let resolved = cursor.resolve(with: .init(string: code))
        let highlights = resolved.highlights()

            func color(for scope: String) -> NSColor? {
                // Exact matches first
                switch scope {
                case "keyword", "keyword.function", "keyword.operator", "keyword.return":
                    return NSColor.systemBlue
                case "type", "type.builtin":
                    return NSColor.systemPurple
                case "function", "function.method", "function.builtin":
                    return NSColor.systemBrown
                case "variable.parameter":
                    return NSColor.systemTeal
                case "comment":
                    return NSColor.systemGreen
                case "string", "string.special":
                    return NSColor.systemRed
                case "number", "float":
                    return NSColor.systemOrange
                case "constant.builtin":
                    return NSColor.systemOrange
                case "boolean":
                    return NSColor.systemBlue
                case "attribute":
                    return NSColor.systemPink
                case "preproc":
                    return NSColor.systemPink
                case "operator":
                    return NSColor.systemCyan
                case "punctuation.delimiter":
                    return NSColor.secondaryLabelColor
                default:
                    break
                }

                // Prefix-based fallback (covers scope variants like keyword.control, string.escape, etc.)
                if scope.hasPrefix("keyword") { return NSColor.systemBlue }
                if scope.hasPrefix("type") { return NSColor.systemPurple }
                if scope.hasPrefix("function") { return NSColor.systemBrown }
                if scope.hasPrefix("comment") { return NSColor.systemGreen }
                if scope.hasPrefix("string") { return NSColor.systemRed }
                if scope.hasPrefix("number") || scope.hasPrefix("float") { return NSColor.systemOrange }
                if scope.hasPrefix("constant") { return NSColor.systemOrange }
                if scope.hasPrefix("attribute") { return NSColor.systemPink }
                if scope.hasPrefix("preproc") { return NSColor.systemPink }
                if scope.hasPrefix("operator") { return NSColor.systemCyan }
                if scope.hasPrefix("punctuation") { return NSColor.secondaryLabelColor }
                return nil
            }

        for namedRange in highlights {
            let normalizedScope = namedRange.name.hasPrefix("@")
            ? String(namedRange.name.dropFirst())
            : namedRange.name
            guard let color = color(for: normalizedScope) else { continue }
            attributed.addAttribute(.foregroundColor, value: color, range: namedRange.range)
        }
        #endif
        
        return attributed
    }

    #if canImport(SwiftTreeSitter)
    // MARK: - Parser Management (only when package is available)

    private func parser(for language: String) -> Parser? {
        if let cached = parsers[language] { return cached }
        guard let lang = tsLanguage(for: language) else { return nil }
        let parser = Parser()
        do { try parser.setLanguage(lang) } catch { return nil }
        parsers[language] = parser
        return parser
    }

    private func languageConfiguration(for language: String) -> LanguageConfiguration? {
        if let cached = languageConfigurations[language] { return cached }

        // IMPORTANT: LanguageConfiguration is responsible for finding highlight queries
        // bundled with the SPM language package (per upstream docs).
        do {
            let config: LanguageConfiguration?
            switch language.lowercased() {
            case "swift":
                guard let tsLang = swiftLanguage()?.tsLanguage else { return nil }
                config = try LanguageConfiguration(tsLang, name: "Swift")
            default:
                config = nil
            }

            if let config {
                languageConfigurations[language] = config
            }
            return config
        } catch {
            print("Failed to create LanguageConfiguration for \(language): \(error)")
            return nil
        }
    }

    private func highlightQuery(for language: String) -> Query? {
        if let cached = highlightQueries[language] { return cached }
        guard let tsLang = tsLanguage(for: language) else { return nil }

        do {
            let query: Query?
            switch language.lowercased() {
            case "swift":
                #if canImport(TreeSitterSwift)
                if let url = TreeSitterSwiftResources.bundle.url(forResource: "highlights", withExtension: "scm", subdirectory: "queries") {
                    query = try tsLang.query(contentsOf: url)
                } else {
                    query = try Query(language: tsLang, data: Data(Self.swiftHighlightsQuery.utf8))
                }
                #else
                query = try Query(language: tsLang, data: Data(Self.swiftHighlightsQuery.utf8))
                #endif
            default:
                query = nil
            }

            if let query {
                highlightQueries[language] = query
            }
            return query
        } catch {
            print("Failed to create highlight query for \(language): \(error)")
            return nil
        }
    }

    private func tsLanguage(for language: String) -> Language? {
        switch language.lowercased() {
        case "swift":
            return swiftLanguage()
        default:
            return nil
        }
    }

    private func swiftLanguage() -> Language? {
        #if canImport(TreeSitterSwift)
        guard let tsLang = tree_sitter_swift() else { return nil }
        return Language(OpaquePointer(tsLang))
        #else
        return nil
        #endif
    }

    private static let swiftHighlightsQuery = #"""
[
  "."
  ";"
  ":"
  ","
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Identifiers
(type_identifier) @type

[
  (self_expression)
  (super_expression)
] @variable.builtin

; Declarations
[
  "func"
  "deinit"
] @keyword.function

[
  (visibility_modifier)
  (member_modifier)
  (function_modifier)
  (property_modifier)
  (parameter_modifier)
  (inheritance_modifier)
  (mutation_modifier)
] @keyword.modifier

(simple_identifier) @variable

(function_declaration
  (simple_identifier) @function.method)

(protocol_function_declaration
  name: (simple_identifier) @function.method)

(init_declaration
  "init" @constructor)

(parameter
  external_name: (simple_identifier) @variable.parameter)

(parameter
  name: (simple_identifier) @variable.parameter)

[
  "protocol"
  "extension"
  "subscript"
  "let"
  "var"
  (throws)
  (where_keyword)
  (else)
  (as_operator)
] @keyword

[
  "enum"
  "struct"
  "class"
  "typealias"
] @keyword.type

(import_declaration
  "import" @keyword.import)

"return" @keyword.return

; Comments
[
  (comment)
  (multiline_comment)
] @comment

; String literals
(line_str_text) @string
(multi_line_str_text) @string

[
  (integer_literal)
  (hex_literal)
  (oct_literal)
  (bin_literal)
] @number

(real_literal) @number.float

(boolean_literal) @boolean

"nil" @constant.builtin
"""#
    #endif
}

