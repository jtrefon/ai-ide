//
//  CodeFormatter.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation

public struct CodeFormatter {
    public static func format(_ code: String, language: CodeLanguage) -> String {
        let indentString = IndentationStyle.current().indentUnit(tabWidth: AppConstants.Editor.tabWidth)

        let strategy: CodeFormattingStrategy = DefaultCodeFormattingStrategy()
        return strategy.format(code: code, language: language, indentUnit: indentString)
    }
}
