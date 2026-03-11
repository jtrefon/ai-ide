//
//  PythonModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class PythonModule: TokenLanguageModule, @unchecked Sendable {
    public init() {
        let configuration = LanguageKeywordRepository.supportConfiguration(for: .python).highlighting
        super.init(
            id: .python,
            fileExtensions: ["py"],
            definition: TokenLanguageDefinition(
                keywords: Set(configuration.keywords),
                typeKeywords: Set(configuration.typeKeywords),
                booleanLiterals: Set(configuration.booleanLiterals),
                nullLiterals: Set(configuration.nullLiterals),
                supportsHashLineComments: true
            )
        )
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return PythonParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .python)
    }
}
