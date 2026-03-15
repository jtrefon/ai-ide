//
//  CSSModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class CSSModule: TokenLanguageModule, @unchecked Sendable {
    public init() {
        let configuration = LanguageKeywordRepository.supportConfiguration(for: .css).highlighting
        super.init(
            id: .css,
            fileExtensions: ["css"],
            definition: TokenLanguageDefinition(
                keywords: Set(configuration.keywords),
                typeKeywords: Set(configuration.typeKeywords),
                booleanLiterals: Set(configuration.booleanLiterals),
                nullLiterals: Set(configuration.nullLiterals)
            ),
            palette: Self.makePalette(for: .css)
        )
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .css)
    }
}
