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
        
        let keywords = [
            "False","None","True","and","as","assert","async","await","break","class","continue","def","del","elif","else","except","finally","for","from","global","if","import","in","is","lambda","nonlocal","not","or","pass","raise","return","try","while","with","yield"
        ]
        
        highlightWholeWords(keywords, color: NSColor.systemBlue, in: attr, code: code)
        
        // Python specific
        applyRegex("#.*", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("\"\"\"[\\s\\S]*?\"\"\"", color: NSColor.systemRed, in: attr, code: code)
        applyRegex("'''[\\s\\S]*?'''", color: NSColor.systemRed, in: attr, code: code)
        
        return attr
    }
    
    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return PythonParser.parse(content: content, resourceId: resourceId)
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .python)
    }
}
