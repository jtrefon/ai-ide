//
//  CSSModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class CSSModule: RegexLanguageModule, @unchecked Sendable {
    public init() {
        super.init(id: .css, fileExtensions: ["css"])
    }
    
    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        
        attr.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        
        // 1. Selectors (Classes, IDs, Tags) - Blue
        // Simplified to match standard CSS selectors more reliably
        applyRegex("(?m)^[ \t]*[.#]?[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=\\{)", color: NSColor.systemBlue, in: attr, code: code)
        // Nested or inline selectors
        applyRegex("(?<=[\\s\\};])[.#]?[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=\\{)", color: NSColor.systemBlue, in: attr, code: code)
        
        // 2. Braces - Lighter Blue (cyan)
        applyRegex("[\\{\\}]", color: NSColor.systemCyan, in: attr, code: code)
        
        // 3. Property Keys - Teal (differentiating from blue selectors)
        applyRegex("(?<=[\\{\\s;])[a-zA-Z-][a-zA-Z0-9-]*\\s*(?=:)", color: NSColor.systemTeal, in: attr, code: code)
        
        // 4. Property Values - Pinkish (System Pink)
        applyRegex("(?<=:)[^;\\}]+", color: NSColor.systemPink, in: attr, code: code)
        
        // 5. Quoted Values (within pinkish values)
        // Quotes themselves - Orange
        applyRegex("['\"]", color: NSColor.systemOrange, in: attr, code: code)
        // Content inside quotes - Different Pink (System Purple as substitute for Magenta)
        applyRegex("(['\"])(?:\\\\.|[^\\1])*?\\1", color: NSColor.systemPurple, in: attr, code: code)
        
        // 6. Numbers and Units (Override pinkish for numbers)
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(px|em|rem|%|vh|vw|s|ms|deg)?\\b", color: NSColor.systemOrange, in: attr, code: code)
        
        // 7. Colors (Hex)
        applyRegex("#[0-9a-fA-F]{3,8}\\b", color: NSColor.systemOrange, in: attr, code: code)
        
        // 8. Comments
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.systemGreen, in: attr, code: code)
        
        return attr
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .css)
    }
}
