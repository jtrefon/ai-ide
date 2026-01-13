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
        
        let jsKeywords = [
            "break","case","catch","class","const","continue","debugger","default","delete","do","else","export","extends","finally","for","function","if","import","in","instanceof","let","new","return","super","switch","this","throw","try","typeof","var","void","while","with","yield","async","await"
        ]
        let tsKeywords = [
                    "interface","type","implements","namespace",
                    "abstract","public","private","protected","readonly"
                ]
        
        highlightWholeWords(jsKeywords, color: NSColor.systemBlue, in: attr, code: code)
        highlightWholeWords(tsKeywords, color: NSColor.systemPurple, in: attr, code: code)
        
        return attr
    }
    
    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return TypeScriptParser.parse(content: content, resourceId: resourceId)
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .typescript)
    }
}
