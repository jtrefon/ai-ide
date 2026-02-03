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

public final class JSONModule: RegexLanguageModule,
                               HighlightPaletteProviding,
                               HighlightDiagnosticsPaletteProviding,
                               @unchecked Sendable {
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

        let defaultColors = JSONTokenHighlighter.DefaultColors(colors: [
            .key: NSColor.labelColor,
            .string: NSColor.labelColor,
            .number: NSColor.labelColor,
            .boolean: NSColor.labelColor,
            .null: NSColor.labelColor,
            .quote: NSColor.labelColor,
            .brace: NSColor.labelColor,
            .bracket: NSColor.labelColor,
            .comma: NSColor.labelColor,
            .colon: NSColor.labelColor
        ])

        let callbacks = JSONTokenHighlighter.Callbacks(
            applyRegex: { [weak self] pattern, color, captureGroup in
                let context = RegexLanguageModule.RegexHighlightContext(attributedString: attr, code: code)
                self?.applyRegex(RegexLanguageModule.RegexHighlightRequest(
                    pattern: pattern,
                    color: color,
                    context: context,
                    captureGroup: captureGroup
                ))
            },
            highlightWholeWords: { [weak self] words, color in
                self?.highlightWholeWords(words, color: color, in: attr, code: code)
            }
        )

        JSONTokenHighlighter.applyAll(
            in: attr,
            code: code,
            palette: highlightPalette,
            defaultColors: defaultColors,
            callbacks: callbacks
        )

        return attr
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .json)
    }
}
