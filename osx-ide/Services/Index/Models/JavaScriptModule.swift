//
//  JavaScriptModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class JavaScriptModule: RegexLanguageModule, @unchecked Sendable {
    public init() {
        super.init(id: .javascript, fileExtensions: ["js", "jsx"])
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

        return attr
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return JavaScriptParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .javascript)
    }
}
