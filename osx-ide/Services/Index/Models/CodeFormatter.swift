//
//  CodeFormatter.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation

public struct CodeFormatter {
    public static func format(_ code: String, language: CodeLanguage) -> String {
        let configuration = LanguageKeywordRepository.formattingConfiguration(for: language)
        let indentString: String
        switch configuration.indentUnitStyle {
        case .tabs:
            indentString = "\t"
        case .spaces:
            indentString = String(repeating: " ", count: max(1, configuration.indentWidth))
        }

        let strategy: CodeFormattingStrategy = DefaultCodeFormattingStrategy()
        let formatted = strategy.format(code: code, language: language, indentUnit: indentString)
        return applyFormattingRules(formatted, configuration: configuration)
    }

    private static func applyFormattingRules(
        _ code: String,
        configuration: LanguageFormattingConfiguration
    ) -> String {
        var lines = code.components(separatedBy: .newlines)

        if configuration.trimTrailingWhitespace {
            lines = lines.map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
        }

        let maxBlankLines = max(0, configuration.maxConsecutiveBlankLines)
        if maxBlankLines >= 0 {
            var collapsed: [String] = []
            var blankRunCount = 0
            for line in lines {
                if line.isEmpty {
                    blankRunCount += 1
                    if blankRunCount <= maxBlankLines {
                        collapsed.append(line)
                    }
                } else {
                    blankRunCount = 0
                    collapsed.append(line)
                }
            }
            lines = collapsed
        }

        var result = lines.joined(separator: "\n")
        if configuration.ensureTrailingNewline, !result.hasSuffix("\n") {
            result.append("\n")
        }
        if !configuration.ensureTrailingNewline, result.hasSuffix("\n") {
            result = String(result.dropLast())
        }
        return result
    }
}
