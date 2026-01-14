//
//  SwiftModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class SwiftModule: RegexLanguageModule, @unchecked Sendable {
    // Force re-indexing
    public init() {
        super.init(id: .swift, fileExtensions: ["swift"])
    }

    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let base = makeBaseAttributedString(code: code, font: font)
        let attr = base.attributed

        applyDoubleQuotedStringHighlighting(color: NSColor.systemRed, in: attr, code: code)
        applyLineAndBlockCommentHighlighting(color: NSColor.systemGreen, in: attr, code: code)
        applyDecimalNumberHighlighting(color: NSColor.systemOrange, in: attr, code: code)

        LanguageKeywordHighlighter.highlight(
            LanguageKeywordRepository.swiftKeywords,
            color: NSColor.systemBlue,
            attr: attr,
            code: code,
            using: self
        )
        LanguageKeywordHighlighter.highlight(
            LanguageKeywordRepository.swiftTypes,
            color: NSColor.systemPurple,
            attr: attr,
            code: code,
            using: self
        )

        return attr
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return SwiftParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .swift)
    }
}
