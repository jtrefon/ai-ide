//
//  PythonModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class PythonModule: RegexLanguageModule, @unchecked Sendable {
    public init() {
        super.init(id: .python, fileExtensions: ["py"])
    }

    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let base = makeBaseAttributedString(code: code, font: font)
        let attr = base.attributed

        applyDoubleAndSingleQuotedStringHighlighting(color: NSColor.systemRed, in: attr, code: code)
        applyDecimalNumberHighlighting(color: NSColor.systemOrange, in: attr, code: code)
        LanguageKeywordHighlighter.highlight(LanguageKeywordHighlighter.HighlightRequest(
            words: LanguageKeywordRepository.python,
            context: LanguageKeywordHighlighter.HighlightContext(
                color: NSColor.systemBlue,
                attributedString: attr,
                code: code,
                helper: self
            )
        ))

        // Python specific
        let regexContext = RegexLanguageModule.RegexHighlightContext(attributedString: attr, code: code)
        applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: "#.*",
            color: NSColor.systemGreen,
            context: regexContext,
            captureGroup: nil
        ))
        applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: "\"\"\"[\\s\\S]*?\"\"\"",
            color: NSColor.systemRed,
            context: regexContext,
            captureGroup: nil
        ))
        applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: "'''[\\s\\S]*?'''",
            color: NSColor.systemRed,
            context: regexContext,
            captureGroup: nil
        ))

        return attr
    }

    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return PythonParser.parse(content: content, resourceId: resourceId)
    }

    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .python)
    }
}
