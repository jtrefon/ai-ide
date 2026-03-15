//
//  HTMLModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class HTMLModule: TokenLanguageModule, @unchecked Sendable {
    public init() {
        let configuration = LanguageKeywordRepository.supportConfiguration(for: .html).highlighting
        super.init(
            id: .html,
            fileExtensions: ["html", "htm"],
            definition: TokenLanguageDefinition(
                keywords: Set(configuration.keywords),
                typeKeywords: Set(configuration.typeKeywords),
                booleanLiterals: Set(configuration.booleanLiterals),
                nullLiterals: Set(configuration.nullLiterals)
            ),
            palette: Self.makePalette(for: .html)
        )
    }
}
