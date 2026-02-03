//
//  TypeScriptModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class TypeScriptModule: RegexLanguageModule, @unchecked Sendable {
    public init() {
        super.init(id: .typescript, fileExtensions: ["ts", "tsx"])
    }

    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let base = makeBaseAttributedString(code: code, font: font)
        let attr = base.attributed

        applyDoubleAndSingleQuotedStringHighlighting(color: NSColor.systemRed, in: attr, code: code)
        applyLineAndBlockCommentHighlighting(color: NSColor.systemGreen, in: attr, code: code)
        applyDecimalNumberHighlighting(color: NSColor.systemOrange, in: attr, code: code)
        LanguageKeywordHighlighter.highlight(LanguageKeywordHighlighter.HighlightRequest(
            words: LanguageKeywordRepository.javascript,
            context: LanguageKeywordHighlighter.HighlightContext(
                color: NSColor.systemBlue,
                attributedString: attr,
                code: code,
                helper: self
            )
        ))
        LanguageKeywordHighlighter.highlight(LanguageKeywordHighlighter.HighlightRequest(
            words: LanguageKeywordRepository.typescriptExtras,
            context: LanguageKeywordHighlighter.HighlightContext(
                color: NSColor.systemPurple,
                attributedString: attr,
                code: code,
                helper: self
            )
        ))

        return attr
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return TypeScriptParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .typescript)
    }
}
