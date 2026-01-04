//
//  CSSModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

// No explicit imports needed if types are in the same module, 
// but added for clarity and to resolve potential indexing issues.
import class Foundation.NSRegularExpression

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

        // 1. Selectors (Classes, IDs, Tags, Pseudo-elements)
        applyRegex("(?m)^[ \t]*:root\\b", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*@[-a-zA-Z]+", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*\\.[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*#[a-zA-Z_][-a-zA-Z0-9_]*\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("(?m)^[ \t]*:{1,2}[a-zA-Z-]+\\s*(?=[,{])", color: NSColor.systemGreen, in: attr, code: code)

        // 2. Braces / punctuation
        applyRegex("[\\{\\}\\[\\]\\(\\);:,]", color: NSColor.systemMint, in: attr, code: code)

        // 3. Property Keys (including custom properties: --foo)
        applyRegex("(?<=[\\{\\s;])(--[a-zA-Z0-9-]+|[a-zA-Z-][a-zA-Z0-9-]*)\\s*(?=:)", color: NSColor.systemBlue, in: attr, code: code, captureGroup: 1)

        // 4. Custom property references
        applyRegex("--[a-zA-Z0-9-]+", color: NSColor.systemBlue, in: attr, code: code)

        // 5. Functions
        applyRegex("\\b[a-zA-Z-]+\\s*(?=\\()", color: NSColor.systemBrown, in: attr, code: code)

        // 6. Hex colors
        applyRegex("#[0-9a-fA-F]{3,8}\\b", color: NSColor.systemOrange, in: attr, code: code)

        // 7. Numbers and Units
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(px|em|rem|%|vh|vw|s|ms|deg)?\\b", color: NSColor.systemYellow, in: attr, code: code)

        // 8. Quoted values (inside)
        applyRegex("\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\"", color: NSColor.systemCyan, in: attr, code: code, captureGroup: 1)
        applyRegex("'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'", color: NSColor.systemCyan, in: attr, code: code, captureGroup: 1)

        // 9. Quotes
        applyRegex("\"", color: NSColor.systemIndigo, in: attr, code: code)
        applyRegex("'", color: NSColor.systemBrown, in: attr, code: code)

        // 10. Bare identifiers in values
        applyRegex("(?<=:)\\s*([a-zA-Z_-][a-zA-Z0-9_-]*)\\b", color: NSColor.systemCyan, in: attr, code: code, captureGroup: 1)

        // 11. Comments
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.tertiaryLabelColor, in: attr, code: code)
        
        return attr
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .css)
    }
}
