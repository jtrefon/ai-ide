//
//  JSONModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

// These types are defined in IndexModels.swift in the same module.
// If SourceKit fails to find them, ensure they are in the same target.

public final class JSONModule: RegexLanguageModule, HighlightPaletteProviding, HighlightDiagnosticsPaletteProviding, @unchecked Sendable {
    public let highlightPalette: HighlightPalette

    public init() {
        var palette = HighlightPalette()
        palette.setColor(.systemGreen, for: .key)
        palette.setColor(.systemTeal, for: .string)
        palette.setColor(.systemOrange, for: .number)
        palette.setColor(.systemBlue, for: .boolean)
        palette.setColor(.systemGray, for: .null)
        palette.setColor(.systemPink, for: .quote)
        palette.setColor(.systemTeal, for: .brace)
        palette.setColor(.systemPurple, for: .bracket)
        palette.setColor(.systemBrown, for: .comma)
        palette.setColor(.systemYellow, for: .colon)
        self.highlightPalette = palette
        
        super.init(id: CodeLanguage.json, fileExtensions: ["json"])
    }

    public var highlightDiagnosticsPalette: [HighlightDiagnosticsSwatch] {
        return [
            HighlightDiagnosticsSwatch(name: "key", color: highlightPalette.color(for: .key) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "string", color: highlightPalette.color(for: .string) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "number", color: highlightPalette.color(for: .number) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "bool", color: highlightPalette.color(for: .boolean) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "null", color: highlightPalette.color(for: .null) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "quote", color: highlightPalette.color(for: .quote) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "brace", color: highlightPalette.color(for: .brace) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "bracket", color: highlightPalette.color(for: .bracket) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "comma", color: highlightPalette.color(for: .comma) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "colon", color: highlightPalette.color(for: .colon) ?? .labelColor)
        ]
    }

    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)

        attr.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        let keyColor = highlightPalette.color(for: .key) ?? .labelColor
        let stringValueColor = highlightPalette.color(for: .string) ?? .labelColor
        let numberValueColor = highlightPalette.color(for: .number) ?? .labelColor
        let booleanValueColor = highlightPalette.color(for: .boolean) ?? .labelColor
        let nullValueColor = highlightPalette.color(for: .null) ?? .labelColor
        let quoteColor = highlightPalette.color(for: .quote) ?? .labelColor
        let curlyBraceColor = highlightPalette.color(for: .brace) ?? .labelColor
        let squareBracketColor = highlightPalette.color(for: .bracket) ?? .labelColor
        let commaColor = highlightPalette.color(for: .comma) ?? .labelColor
        let colonColor = highlightPalette.color(for: .colon) ?? .labelColor

        // 1. Strings (apply generic string color first)
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: stringValueColor, in: attr, code: code)

        // 2. Braces, brackets, commas, colons (structural tokens)
        applyRegex("[\\{\\}]", color: curlyBraceColor, in: attr, code: code)
        applyRegex("[\\[\\]]", color: squareBracketColor, in: attr, code: code)
        applyRegex(",", color: commaColor, in: attr, code: code)
        applyRegex(":", color: colonColor, in: attr, code: code)

        // 3. Keys - override strings with indigo (just the content)
        applyRegex("\"([^\"]+)\"\\s*:", color: keyColor, in: attr, code: code, captureGroup: 1)

        // 4. String values (content only, after colons)
        applyRegex(":\\s*\"([^\"]+)\"", color: stringValueColor, in: attr, code: code, captureGroup: 1)

        // 5. Numbers
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", color: numberValueColor, in: attr, code: code)

        // 6. Boolean values
        highlightWholeWords(["true", "false"], color: booleanValueColor, in: attr, code: code)

        // 7. Null value
        highlightWholeWords(["null"], color: nullValueColor, in: attr, code: code)
        
        // 8. Quotes
        applyRegex("\"", color: quoteColor, in: attr, code: code)

        return attr
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .json)
    }
}
