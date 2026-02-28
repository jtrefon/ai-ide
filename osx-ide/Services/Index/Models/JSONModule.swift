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

public final class JSONModule: TokenLanguageModule,
                               HighlightPaletteProviding,
                               @unchecked Sendable {
    public let highlightPalette: HighlightPalette

    public init() {
        self.highlightPalette = Self.makePalette(language: .json)
        let configuration = LanguageKeywordRepository.supportConfiguration(for: .json).highlighting
        super.init(
            id: .json,
            fileExtensions: ["json"],
            definition: TokenLanguageDefinition(
                keywords: Set(configuration.keywords),
                typeKeywords: Set(configuration.typeKeywords),
                booleanLiterals: Set(configuration.booleanLiterals),
                nullLiterals: Set(configuration.nullLiterals)
            ),
            palette: highlightPalette
        )
    }

    private static func makePalette(language: CodeLanguage) -> HighlightPalette {
        var palette = HighlightPalette()
        for role in HighlightRole.allCases {
            if let color = LanguageKeywordRepository.tokenColor(for: language, role: role) {
                palette.setColor(color, for: role)
            }
        }

        if palette.color(for: .string) == nil { palette.setColor(.systemTeal, for: .string) }
        if palette.color(for: .number) == nil { palette.setColor(.systemOrange, for: .number) }
        if palette.color(for: .boolean) == nil { palette.setColor(.systemBlue, for: .boolean) }
        if palette.color(for: .null) == nil { palette.setColor(.systemGray, for: .null) }
        if palette.color(for: .key) == nil { palette.setColor(.systemGreen, for: .key) }
        return palette
    }

    public override var highlightDiagnosticsPalette: [HighlightDiagnosticsSwatch] {
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
        let attributed = NSMutableAttributedString(attributedString: super.highlight(code, font: font))
        guard let keyColor = highlightPalette.color(for: .key) else { return attributed }

        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            guard color == (self.highlightPalette.color(for: .string) ?? .systemTeal) else { return }
            guard self.isJSONStringKey(range: range, in: ns) else { return }
            attributed.addAttribute(.foregroundColor, value: keyColor, range: range)
        }

        return attributed
    }

    private func isJSONStringKey(range: NSRange, in text: NSString) -> Bool {
        let afterStringIndex = range.location + range.length
        guard afterStringIndex <= text.length else { return false }

        var cursor = afterStringIndex
        while cursor < text.length {
            let scalar = text.character(at: cursor)
            if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(scalar)!) {
                cursor += 1
                continue
            }
            return Character(UnicodeScalar(scalar)!) == ":"
        }

        return false
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .json)
    }
}
