import AppKit
import Foundation

struct TokenLanguageConfiguration: Codable {
    let keywords: [String]
    let typeKeywords: [String]
    let booleanLiterals: [String]
    let nullLiterals: [String]

    static func parse(json: String) -> TokenLanguageConfiguration? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TokenLanguageConfiguration.self, from: data)
    }
}

enum LanguageIndentUnitStyle: String, Codable {
    case tabs
    case spaces
}

struct LanguageStylingConfiguration: Codable {
    let tokenColors: [String: String]
    let fontTraitsByRole: [String: String]
    let preferredFontFamily: String?

    static let `default` = LanguageStylingConfiguration(
        tokenColors: [:],
        fontTraitsByRole: [:],
        preferredFontFamily: nil
    )
}

struct LanguageFormattingConfiguration: Codable {
    let indentUnitStyle: LanguageIndentUnitStyle
    let indentWidth: Int
    let trimTrailingWhitespace: Bool
    let ensureTrailingNewline: Bool
    let maxConsecutiveBlankLines: Int

    static let `default` = LanguageFormattingConfiguration(
        indentUnitStyle: .spaces,
        indentWidth: 4,
        trimTrailingWhitespace: true,
        ensureTrailingNewline: true,
        maxConsecutiveBlankLines: 1
    )
}

struct LintRuleDefinition: Codable {
    let id: String
    let severity: String
    let enabled: Bool
    let message: String
    let options: [String: String]
}

struct LanguageLintingConfiguration: Codable {
    let registry: String
    let rules: [LintRuleDefinition]

    static let `default` = LanguageLintingConfiguration(registry: "builtin", rules: [])
}

struct LanguageSupportConfiguration: Codable {
    let schemaVersion: Int
    let language: String
    let highlighting: TokenLanguageConfiguration
    let styling: LanguageStylingConfiguration
    let formatting: LanguageFormattingConfiguration
    let linting: LanguageLintingConfiguration
}

struct HighlightThemeConfiguration: Codable {
    let schemaVersion: Int
    let themeName: String
    let languages: [String: [String: String]]
}

struct TokenSpan {
    let role: HighlightRole
    let range: NSRange
}

enum CStyleTokenizer {
    static func tokenize(
        code: String,
        keywords: Set<String>,
        typeKeywords: Set<String>,
        booleanLiterals: Set<String>,
        nullLiterals: Set<String>,
        supportsHashLineComments: Bool = false
    ) -> [TokenSpan] {
        let scanner = CStyleScanner(code: code)
        var spans: [TokenSpan] = []

        while !scanner.isAtEnd {
            if let span = scanComment(scanner, supportsHashLineComments: supportsHashLineComments) {
                spans.append(span)
                continue
            }

            if let span = scanString(scanner) {
                spans.append(span)
                continue
            }

            if let span = scanNumber(scanner) {
                spans.append(span)
                continue
            }

            if let span = scanWordRole(
                scanner,
                keywords: keywords,
                typeKeywords: typeKeywords,
                booleanLiterals: booleanLiterals,
                nullLiterals: nullLiterals
            ) {
                spans.append(span)
                continue
            }

            scanner.advance()
        }

        return spans
    }

    private static func scanComment(_ scanner: CStyleScanner, supportsHashLineComments: Bool) -> TokenSpan? {
        if supportsHashLineComments, scanner.current == "#" {
            let start = scanner.position
            scanner.advance()
            while !scanner.isAtEnd, scanner.current != "\n", scanner.current != "\r" {
                scanner.advance()
            }
            return TokenSpan(role: .comment, range: NSRange(location: start, length: scanner.position - start))
        }

        guard scanner.current == "/" else { return nil }

        if scanner.peek() == "/" {
            let start = scanner.position
            scanner.advance(by: 2)
            while !scanner.isAtEnd, scanner.current != "\n", scanner.current != "\r" {
                scanner.advance()
            }
            return TokenSpan(role: .comment, range: NSRange(location: start, length: scanner.position - start))
        }

        if scanner.peek() == "*" {
            let start = scanner.position
            scanner.advance(by: 2)
            while !scanner.isAtEnd {
                if scanner.current == "*", scanner.peek() == "/" {
                    scanner.advance(by: 2)
                    break
                }
                scanner.advance()
            }
            return TokenSpan(role: .comment, range: NSRange(location: start, length: scanner.position - start))
        }

        return nil
    }

    private static func scanString(_ scanner: CStyleScanner) -> TokenSpan? {
        guard scanner.current == "\"" || scanner.current == "'" || scanner.current == "`" else {
            return nil
        }

        let start = scanner.position
        let quote = scanner.current
        scanner.advance()

        while !scanner.isAtEnd {
            if scanner.current == "\\" {
                scanner.advance(by: min(2, scanner.remainingLength))
                continue
            }

            if scanner.current == quote {
                scanner.advance()
                break
            }

            scanner.advance()
        }

        return TokenSpan(role: .string, range: NSRange(location: start, length: scanner.position - start))
    }

    private static func scanNumber(_ scanner: CStyleScanner) -> TokenSpan? {
        guard scanner.current.isAsciiDigit else { return nil }

        let start = scanner.position
        while !scanner.isAtEnd, scanner.current.isAsciiDigit {
            scanner.advance()
        }

        if !scanner.isAtEnd, scanner.current == ".", scanner.peek()?.isAsciiDigit == true {
            scanner.advance()
            while !scanner.isAtEnd, scanner.current.isAsciiDigit {
                scanner.advance()
            }
        }

        return TokenSpan(role: .number, range: NSRange(location: start, length: scanner.position - start))
    }

    private static func scanWordRole(
        _ scanner: CStyleScanner,
        keywords: Set<String>,
        typeKeywords: Set<String>,
        booleanLiterals: Set<String>,
        nullLiterals: Set<String>
    ) -> TokenSpan? {
        guard scanner.current.isIdentifierStart else { return nil }

        let start = scanner.position
        scanner.advance()
        while !scanner.isAtEnd, scanner.current.isIdentifierContinue {
            scanner.advance()
        }

        let word = scanner.substring(from: start, to: scanner.position)
        let range = NSRange(location: start, length: scanner.position - start)

        if keywords.contains(word) { return TokenSpan(role: .keyword, range: range) }
        if typeKeywords.contains(word) { return TokenSpan(role: .type, range: range) }
        if booleanLiterals.contains(word) { return TokenSpan(role: .boolean, range: range) }
        if nullLiterals.contains(word) { return TokenSpan(role: .null, range: range) }
        return nil
    }
}

final class CStyleScanner {
    private let text: NSString
    private(set) var position: Int = 0

    init(code: String) {
        self.text = code as NSString
    }

    var isAtEnd: Bool {
        position >= text.length
    }

    var remainingLength: Int {
        max(0, text.length - position)
    }

    var current: Character {
        char(at: position)
    }

    func peek() -> Character? {
        let next = position + 1
        guard next < text.length else { return nil }
        return char(at: next)
    }

    func advance() {
        position = min(text.length, position + 1)
    }

    func advance(by count: Int) {
        position = min(text.length, position + count)
    }

    func substring(from start: Int, to end: Int) -> String {
        guard end > start else { return "" }
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    private func char(at index: Int) -> Character {
        let value = Int(text.character(at: index))
        guard let scalar = UnicodeScalar(value) else { return "\0" }
        return Character(scalar)
    }
}

private extension Character {
    var isAsciiDigit: Bool {
        ("0"..."9").contains(self)
    }

    var isIdentifierStart: Bool {
        guard let scalar = String(self).unicodeScalars.first else { return false }
        return CharacterSet.letters.contains(scalar) || self == "_" || self == "$"
    }

    var isIdentifierContinue: Bool {
        isIdentifierStart || isAsciiDigit
    }
}

enum LanguageKeywordRepository {
    private struct LegacyTokenLanguageSupportConfiguration: Codable {
        let keywords: [String]
        let typeKeywords: [String]
        let booleanLiterals: [String]
        let nullLiterals: [String]
    }

    private static var environmentConfigurationDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["OSX_IDE_HIGHLIGHT_DEFINITIONS_DIR"], !directory.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: directory, isDirectory: true)
    }

    private static var bundleConfigurationDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Highlighting/Languages", isDirectory: true)
    }

    private static var repositoryConfigurationDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Models
            .deletingLastPathComponent() // Index
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // osx-ide module root
            .appendingPathComponent("Highlighting/Languages", isDirectory: true)
    }

    private static var processWorkingDirectoryConfigurationDirectory: URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("osx-ide/Highlighting/Languages", isDirectory: true),
            cwd.appendingPathComponent("Highlighting/Languages", isDirectory: true)
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private static var configurationDirectoriesInLookupOrder: [URL] {
        [
            environmentConfigurationDirectory,
            bundleConfigurationDirectory,
            processWorkingDirectoryConfigurationDirectory,
            repositoryConfigurationDirectory
        ].compactMap { $0 }
    }

    private static var environmentThemeDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["OSX_IDE_HIGHLIGHT_THEMES_DIR"], !directory.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: directory, isDirectory: true)
    }

    private static var bundleThemeDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Highlighting/Themes", isDirectory: true)
    }

    private static var repositoryThemeDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Models
            .deletingLastPathComponent() // Index
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // osx-ide module root
            .appendingPathComponent("Highlighting/Themes", isDirectory: true)
    }

    private static var processWorkingDirectoryThemeDirectory: URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("osx-ide/Highlighting/Themes", isDirectory: true),
            cwd.appendingPathComponent("Highlighting/Themes", isDirectory: true)
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private static var themeDirectoriesInLookupOrder: [URL] {
        [
            environmentThemeDirectory,
            bundleThemeDirectory,
            processWorkingDirectoryThemeDirectory,
            repositoryThemeDirectory
        ].compactMap { $0 }
    }

    private static func loadExternalConfiguration(
        named filename: String,
        language: CodeLanguage,
        fallbackHighlighting: TokenLanguageConfiguration
    ) -> LanguageSupportConfiguration? {
        for directory in configurationDirectoriesInLookupOrder {
            let fileURL = directory.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            if let configuration = parseLanguageSupportConfiguration(
                data: data,
                language: language,
                fallbackHighlighting: fallbackHighlighting
            ) {
                return configuration
            }
        }
        return nil
    }

    private static func loadRequiredSupportConfiguration(
        named filename: String,
        language: CodeLanguage,
        fallbackHighlighting: TokenLanguageConfiguration
    ) -> LanguageSupportConfiguration {
        guard let configuration = loadExternalConfiguration(
            named: filename,
            language: language,
            fallbackHighlighting: fallbackHighlighting
        ) else {
            let diagnostics = configurationDirectoriesInLookupOrder
                .map { directory -> String in
                    let target = directory.appendingPathComponent(filename)
                    let exists = FileManager.default.fileExists(atPath: target.path)
                    return "\(target.path) [exists=\(exists)]"
                }
                .joined(separator: ", ")
            fatalError(
                "Missing required language support configuration: \(filename). Lookup paths: \(diagnostics)"
            )
        }
        return configuration
    }

    private static func parseLanguageSupportConfiguration(
        data: Data,
        language: CodeLanguage,
        fallbackHighlighting: TokenLanguageConfiguration
    ) -> LanguageSupportConfiguration? {
        if let supportConfiguration = try? JSONDecoder().decode(LanguageSupportConfiguration.self, from: data) {
            return supportConfiguration
        }

        guard let legacy = try? JSONDecoder().decode(LegacyTokenLanguageSupportConfiguration.self, from: data) else {
            return nil
        }

        return LanguageSupportConfiguration(
            schemaVersion: 1,
            language: language.rawValue,
            highlighting: TokenLanguageConfiguration(
                keywords: legacy.keywords,
                typeKeywords: legacy.typeKeywords,
                booleanLiterals: legacy.booleanLiterals,
                nullLiterals: legacy.nullLiterals
            ),
            styling: .default,
            formatting: .default,
            linting: .default
        )
    }

    private static func loadThemeConfiguration(named filename: String) -> HighlightThemeConfiguration? {
        for directory in themeDirectoriesInLookupOrder {
            let fileURL = directory.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            if let configuration = try? JSONDecoder().decode(HighlightThemeConfiguration.self, from: data) {
                return configuration
            }
        }
        return nil
    }

    static func tokenColor(for language: CodeLanguage, role: HighlightRole) -> NSColor? {
        if let roleHex = supportConfiguration(for: language).styling.tokenColors[role.rawValue] {
            return NSColor(hex: roleHex)
        }

        guard let roleHex = defaultThemeConfiguration?.languages[language.rawValue]?[role.rawValue] else {
            return nil
        }
        return NSColor(hex: roleHex)
    }

    static func supportConfiguration(for language: CodeLanguage) -> LanguageSupportConfiguration {
        switch language {
        case .javascript:
            return javascriptSupportConfiguration
        case .typescript:
            return typeScriptSupportConfiguration
        case .swift:
            return swiftSupportConfiguration
        case .python:
            return pythonSupportConfiguration
        case .html:
            return htmlSupportConfiguration
        case .css:
            return cssSupportConfiguration
        case .json:
            return jsonSupportConfiguration
        case .yaml, .markdown, .unknown:
            return LanguageSupportConfiguration(
                schemaVersion: 1,
                language: language.rawValue,
                highlighting: TokenLanguageConfiguration(keywords: [], typeKeywords: [], booleanLiterals: [], nullLiterals: []),
                styling: .default,
                formatting: .default,
                linting: .default
            )
        }
    }

    static func formattingConfiguration(for language: CodeLanguage) -> LanguageFormattingConfiguration {
        supportConfiguration(for: language).formatting
    }

    static func lintRules(for language: CodeLanguage) -> [LintRuleDefinition] {
        supportConfiguration(for: language).linting.rules
    }

    private static let defaultThemeConfiguration: HighlightThemeConfiguration? =
        loadThemeConfiguration(named: "default.json")

    static let javascript: [String] = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
        "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try",
        "typeof", "var", "void", "while", "with", "yield", "async", "await"
    ]

    static let typescriptExtras: [String] = [
        "interface", "type", "implements", "namespace", "abstract",
        "public", "private", "protected", "readonly"
    ]

    static let javascriptConfiguration: TokenLanguageConfiguration = {
        javascriptSupportConfiguration.highlighting
    }()

    static let javascriptSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: javascript,
            typeKeywords: [],
            booleanLiterals: ["true", "false"],
            nullLiterals: ["null", "undefined"]
        )

        return loadRequiredSupportConfiguration(
            named: "javascript.json",
            language: .javascript,
            fallbackHighlighting: fallback
        )
    }()

    static let typeScriptConfiguration: TokenLanguageConfiguration = {
        typeScriptSupportConfiguration.highlighting
    }()

    static let typeScriptSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: javascript + typescriptExtras,
            typeKeywords: ["string", "number", "boolean", "any", "unknown", "never", "void"],
            booleanLiterals: ["true", "false"],
            nullLiterals: ["null", "undefined"]
        )

        return loadRequiredSupportConfiguration(
            named: "typescript.json",
            language: .typescript,
            fallbackHighlighting: fallback
        )
    }()

    static let swiftSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: swiftKeywords,
            typeKeywords: swiftTypes,
            booleanLiterals: ["true", "false"],
            nullLiterals: ["nil"]
        )
        return loadRequiredSupportConfiguration(
            named: "swift.json",
            language: .swift,
            fallbackHighlighting: fallback
        )
    }()

    static let pythonSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: python,
            typeKeywords: [],
            booleanLiterals: ["True", "False"],
            nullLiterals: ["None"]
        )
        return loadRequiredSupportConfiguration(
            named: "python.json",
            language: .python,
            fallbackHighlighting: fallback
        )
    }()

    static let htmlSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: ["html", "head", "body", "div", "span", "script", "style", "meta", "link"],
            typeKeywords: [],
            booleanLiterals: [],
            nullLiterals: []
        )
        return loadRequiredSupportConfiguration(
            named: "html.json",
            language: .html,
            fallbackHighlighting: fallback
        )
    }()

    static let cssSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: ["@media", "@import", "@supports", "@keyframes", "@font-face"],
            typeKeywords: ["px", "em", "rem", "vh", "vw", "%", "fr"],
            booleanLiterals: [],
            nullLiterals: []
        )
        return loadRequiredSupportConfiguration(
            named: "css.json",
            language: .css,
            fallbackHighlighting: fallback
        )
    }()

    static let jsonSupportConfiguration: LanguageSupportConfiguration = {
        let fallback = TokenLanguageConfiguration(
            keywords: [],
            typeKeywords: [],
            booleanLiterals: ["true", "false"],
            nullLiterals: ["null"]
        )
        return loadRequiredSupportConfiguration(
            named: "json.json",
            language: .json,
            fallbackHighlighting: fallback
        )
    }()

    static let swiftKeywords: [String] = [
        "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
        "if", "else", "for", "while", "repeat", "switch", "case", "default", "break",
        "continue", "defer", "do", "catch", "throw", "throws", "rethrows", "try", "in",
        "where", "return", "as", "is", "nil", "true", "false", "init", "deinit",
        "subscript", "typealias", "associatedtype", "mutating", "nonmutating", "static",
        "final", "open", "public", "internal", "fileprivate", "private", "guard", "some",
        "any", "actor", "await", "async", "yield", "inout"
    ]

    static let swiftTypes: [String] = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Double", "Bool", "String", "Character",
        "Array", "Dictionary", "Set", "Optional", "Void", "Any", "AnyObject"
    ]

    static let python: [String] = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
        "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
        "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass",
        "raise", "return", "try", "while", "with", "yield"
    ]
}

private extension NSColor {
    convenience init?(hex: String) {
        let normalizedHex = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard normalizedHex.count == 6, let value = UInt32(normalizedHex, radix: 16) else {
            return nil
        }

        let red = CGFloat((value & 0xFF0000) >> 16) / 255
        let green = CGFloat((value & 0x00FF00) >> 8) / 255
        let blue = CGFloat(value & 0x0000FF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
