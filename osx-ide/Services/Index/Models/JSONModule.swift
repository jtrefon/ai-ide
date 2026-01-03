//
//  JSONModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class JSONModule: RegexLanguageModule, @unchecked Sendable {
    public init() {
        super.init(id: .json, fileExtensions: ["json"])
    }
    
    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        
        attr.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        
        // Keys
        applyRegex("\"([^\"]+)\"\\s*:(?=\\s)", color: NSColor.systemPurple, in: attr, code: code, captureGroup: 1)
        // String values
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor.systemRed, in: attr, code: code)
        // Numbers
        applyRegex("\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", color: NSColor.systemOrange, in: attr, code: code)
        // Booleans and null
        highlightWholeWords(["true","false","null"], color: NSColor.systemBlue, in: attr, code: code)
        
        return attr
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .json)
    }
}
