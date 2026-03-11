//
//  JavaScriptModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class JavaScriptModule: TokenLanguageModule, @unchecked Sendable {
    public init() {
        let configuration = LanguageKeywordRepository.javascriptConfiguration
        super.init(
            id: .javascript,
            fileExtensions: ["js", "jsx"],
            definition: TokenLanguageDefinition(
                keywords: Set(configuration.keywords),
                typeKeywords: Set(configuration.typeKeywords),
                booleanLiterals: Set(configuration.booleanLiterals),
                nullLiterals: Set(configuration.nullLiterals)
            ),
            palette: Self.makePalette(language: .javascript)
        )
    }

    private static func makePalette(language: CodeLanguage) -> HighlightPalette {
        var palette = HighlightPalette()
        for role in HighlightRole.allCases {
            if let color = LanguageKeywordRepository.tokenColor(for: language, role: role) {
                palette.setColor(color, for: role)
            }
        }
        return palette
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return JavaScriptParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .javascript)
    }
}
