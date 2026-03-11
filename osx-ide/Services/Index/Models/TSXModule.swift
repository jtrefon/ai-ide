import AppKit
import Foundation

public final class TSXModule: TokenLanguageModule, @unchecked Sendable {
    public init() {
        let configuration = LanguageKeywordRepository.tsxConfiguration
        super.init(
            id: .tsx,
            fileExtensions: ["tsx"],
            definition: TokenLanguageDefinition(
                keywords: Set(configuration.keywords),
                typeKeywords: Set(configuration.typeKeywords),
                booleanLiterals: Set(configuration.booleanLiterals),
                nullLiterals: Set(configuration.nullLiterals)
            ),
            palette: Self.makePalette(language: .tsx)
        )
    }

    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let attributed = NSMutableAttributedString(attributedString: super.highlight(code, font: font))
        applyJSXMarkupHighlighting(in: attributed, code: code)
        return attributed
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        TypeScriptParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        CodeFormatter.format(code, language: .tsx)
    }

    public override var highlightDiagnosticsPalette: [HighlightDiagnosticsSwatch] {
        super.highlightDiagnosticsPalette + [
            HighlightDiagnosticsSwatch(name: "tag", color: color(for: .tag) ?? .labelColor),
            HighlightDiagnosticsSwatch(name: "attribute", color: color(for: .attribute) ?? .labelColor)
        ]
    }

    private static func makePalette(language: CodeLanguage) -> HighlightPalette {
        var palette = HighlightPalette()
        for role in HighlightRole.allCases {
            if let tokenColor = LanguageKeywordRepository.tokenColor(for: language, role: role) {
                palette.setColor(tokenColor, for: role)
            }
        }
        return palette
    }

    private func applyJSXMarkupHighlighting(in attributed: NSMutableAttributedString, code: String) {
        let source = code as NSString
        let length = source.length
        var index = 0

        while index < length {
            guard source.character(at: index) == 60 else { // <
                index += 1
                continue
            }

            let nextIndex = index + 1
            guard nextIndex < length else {
                index += 1
                continue
            }

            let nextCharacter = source.character(at: nextIndex)
            let isOpeningTag = isIdentifierStart(nextCharacter)
            let isClosingTag = nextCharacter == 47 // /
            guard isOpeningTag || isClosingTag else {
                index += 1
                continue
            }

            var cursor = nextIndex
            if isClosingTag {
                cursor += 1
            }

            let tagNameStart = cursor
            while cursor < length, isIdentifierContinue(source.character(at: cursor)) {
                cursor += 1
            }

            if cursor > tagNameStart {
                let tagName = source.substring(with: NSRange(location: tagNameStart, length: cursor - tagNameStart))
                let tagRole: HighlightRole = isComponentTagName(tagName) ? .type : .tag
                let tagColor = color(for: tagRole)
                if let tagColor {
                attributed.addAttribute(
                    .foregroundColor,
                    value: tagColor,
                    range: NSRange(location: tagNameStart, length: cursor - tagNameStart)
                )
                }
            }

            while cursor < length {
                let scalar = source.character(at: cursor)
                if scalar == 34 || scalar == 39 { // " or '
                    let quote = scalar
                    cursor += 1
                    while cursor < length {
                        let current = source.character(at: cursor)
                        if current == 92 { // \
                            cursor = min(length, cursor + 2)
                            continue
                        }
                        if current == quote {
                            cursor += 1
                            break
                        }
                        cursor += 1
                    }
                    continue
                }

                if scalar == 123 { // {
                    cursor = scanPastExpressionBlock(in: source, from: cursor, length: length)
                    continue
                }

                if scalar == 62 { // >
                    cursor += 1
                    break
                }

                if isIdentifierStart(scalar) {
                    let attributeStart = cursor
                    cursor += 1
                    while cursor < length, isIdentifierContinue(source.character(at: cursor)) {
                        cursor += 1
                    }

                    if let attributeColor = color(for: .attribute) {
                        attributed.addAttribute(
                            .foregroundColor,
                            value: attributeColor,
                            range: NSRange(location: attributeStart, length: cursor - attributeStart)
                        )
                    }
                    continue
                }

                cursor += 1
            }

            index = max(index + 1, cursor)
        }
    }

    private func isIdentifierStart(_ scalar: unichar) -> Bool {
        scalar == 95 || scalar == 36 || // _ or $
            (65...90).contains(Int(scalar)) ||
            (97...122).contains(Int(scalar))
    }

    private func isIdentifierContinue(_ scalar: unichar) -> Bool {
        isIdentifierStart(scalar) || scalar == 45 || scalar == 58 || // - or :
            (48...57).contains(Int(scalar))
    }

    private func scanPastExpressionBlock(in source: NSString, from index: Int, length: Int) -> Int {
        var cursor = index + 1
        var depth = 1

        while cursor < length, depth > 0 {
            let scalar = source.character(at: cursor)
            if scalar == 34 || scalar == 39 { // " or '
                let quote = scalar
                cursor += 1
                while cursor < length {
                    let current = source.character(at: cursor)
                    if current == 92 { // \
                        cursor = min(length, cursor + 2)
                        continue
                    }
                    if current == quote {
                        cursor += 1
                        break
                    }
                    cursor += 1
                }
                continue
            }

            if scalar == 123 { // {
                depth += 1
            } else if scalar == 125 { // }
                depth -= 1
            }
            cursor += 1
        }

        return cursor
    }

    private func isComponentTagName(_ tagName: String) -> Bool {
        guard let firstScalar = tagName.unicodeScalars.first else { return false }
        return CharacterSet.uppercaseLetters.contains(firstScalar)
    }
}
