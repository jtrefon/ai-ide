import AppKit
import Foundation

public struct TokenLanguageDefinition: Sendable {
    public let keywords: Set<String>
    public let typeKeywords: Set<String>
    public let booleanLiterals: Set<String>
    public let nullLiterals: Set<String>
    public let supportsHashLineComments: Bool

    public init(
        keywords: Set<String>,
        typeKeywords: Set<String> = [],
        booleanLiterals: Set<String> = ["true", "false"],
        nullLiterals: Set<String> = ["null"],
        supportsHashLineComments: Bool = false
    ) {
        self.keywords = keywords
        self.typeKeywords = typeKeywords
        self.booleanLiterals = booleanLiterals
        self.nullLiterals = nullLiterals
        self.supportsHashLineComments = supportsHashLineComments
    }
}

open class TokenLanguageModule: LanguageModule, HighlightDiagnosticsPaletteProviding, @unchecked Sendable {
    public let id: CodeLanguage
    public let fileExtensions: [String]
    private let definition: TokenLanguageDefinition
    private let palette: HighlightPalette?

    public init(
        id: CodeLanguage,
        fileExtensions: [String],
        definition: TokenLanguageDefinition,
        palette: HighlightPalette? = nil
    ) {
        self.id = id
        self.fileExtensions = fileExtensions
        self.definition = definition
        self.palette = palette
    }

    open func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let (attributed, _) = AttributedStringStyler.makeBaseAttributedString(code: code, font: font)
        let tokens = CStyleTokenizer.tokenize(
            code: code,
            keywords: definition.keywords,
            typeKeywords: definition.typeKeywords,
            booleanLiterals: definition.booleanLiterals,
            nullLiterals: definition.nullLiterals,
            supportsHashLineComments: definition.supportsHashLineComments
        )

        for token in tokens {
            guard let color = color(for: token.role) else { continue }
            attributed.addAttribute(.foregroundColor, value: color, range: token.range)
        }

        return attributed
    }

    open func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        []
    }

    open func format(_ code: String) -> String {
        code
    }

    public var highlightDiagnosticsPalette: [HighlightDiagnosticsSwatch] {
        [
            HighlightDiagnosticsSwatch(name: "keyword", color: color(for: .keyword) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "type", color: color(for: .type) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "boolean", color: color(for: .boolean) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "null", color: color(for: .null) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "number", color: color(for: .number) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "string", color: color(for: .string) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "comment", color: color(for: .comment) ?? .labelColor)
        ]
    }

    func color(for role: HighlightRole) -> NSColor? {
        if let paletteColor = palette?.color(for: role) {
            return paletteColor
        }

        switch role {
        case .keyword:
            return .systemBlue
        case .type:
            return .systemPurple
        case .boolean, .null, .number:
            return .systemOrange
        case .string:
            return .systemRed
        case .comment:
            return .systemGreen
        default:
            return nil
        }
    }
}
