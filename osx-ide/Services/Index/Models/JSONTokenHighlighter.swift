import Foundation
import AppKit

public enum JSONTokenHighlighter {
    public struct DefaultColors {
        private let colors: [HighlightRole: NSColor]

        public init(colors: [HighlightRole: NSColor]) {
            self.colors = colors
        }

        public func color(for role: HighlightRole) -> NSColor {
            colors[role] ?? NSColor.labelColor
        }
    }

    public struct Callbacks {
        public let applyRegex: (_ pattern: String, _ color: NSColor, _ captureGroup: Int?) -> Void
        public let highlightWholeWords: (_ words: [String], _ color: NSColor) -> Void

        public init(
            applyRegex: @escaping (_ pattern: String, _ color: NSColor, _ captureGroup: Int?) -> Void,
            highlightWholeWords: @escaping (_ words: [String], _ color: NSColor) -> Void
        ) {
            self.applyRegex = applyRegex
            self.highlightWholeWords = highlightWholeWords
        }
    }

    public static func applyAll(
        in attr: NSMutableAttributedString,
        code: String,
        palette: HighlightPalette?,
        defaultColors: DefaultColors,
        callbacks: Callbacks
    ) {
        let keyColor = palette?.color(for: HighlightRole.key) ?? defaultColors.color(for: .key)
        let stringValueColor = palette?.color(for: HighlightRole.string) ?? defaultColors.color(for: .string)
        let numberValueColor = palette?.color(for: HighlightRole.number) ?? defaultColors.color(for: .number)
        let booleanValueColor = palette?.color(for: HighlightRole.boolean) ?? defaultColors.color(for: .boolean)
        let nullValueColor = palette?.color(for: HighlightRole.null) ?? defaultColors.color(for: .null)
        let quoteColor = palette?.color(for: HighlightRole.quote) ?? defaultColors.color(for: .quote)
        let curlyBraceColor = palette?.color(for: HighlightRole.brace) ?? defaultColors.color(for: .brace)
        let squareBracketColor = palette?.color(for: HighlightRole.bracket) ?? defaultColors.color(for: .bracket)
        let commaColor = palette?.color(for: HighlightRole.comma) ?? defaultColors.color(for: .comma)
        let colonColor = palette?.color(for: HighlightRole.colon) ?? defaultColors.color(for: .colon)

        callbacks.applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", stringValueColor, nil)

        callbacks.applyRegex("[\\{\\}]", curlyBraceColor, nil)
        callbacks.applyRegex("[\\[\\]]", squareBracketColor, nil)
        callbacks.applyRegex(",", commaColor, nil)
        callbacks.applyRegex(":", colonColor, nil)

        callbacks.applyRegex("\"([^\"]+)\"\\s*:", keyColor, 1)

        callbacks.applyRegex(":\\s*\"([^\"]+)\"", stringValueColor, 1)

        callbacks.applyRegex("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", numberValueColor, nil)

        callbacks.highlightWholeWords(["true", "false"], booleanValueColor)
        callbacks.highlightWholeWords(["null"], nullValueColor)

        callbacks.applyRegex("\"", quoteColor, nil)
    }
}
