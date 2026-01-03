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
        let attr = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        
        attr.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        
        applyGenericHighlighting(in: attr, code: code)
        
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
    
    private func applyGenericHighlighting(in attr: NSMutableAttributedString, code: String) {
        // Strings
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor.systemRed, in: attr, code: code)
        applyRegex("'(?:\\\\.|[^'\\\\])*'", color: NSColor.systemRed, in: attr, code: code)
        // Numbers
        applyRegex("\\b\\d+(?:\\.\\d+)?\\b", color: NSColor.systemOrange, in: attr, code: code)
    }
    
    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return PythonParser.parse(content: content, resourceId: resourceId)
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .python)
    }
}
