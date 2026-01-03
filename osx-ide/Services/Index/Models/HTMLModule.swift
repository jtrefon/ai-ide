//
//  HTMLModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class HTMLModule: RegexLanguageModule, @unchecked Sendable {
    public init() {
        super.init(id: .html, fileExtensions: ["html", "htm"])
    }
    
    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        
        attr.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        
        // Tags and tag names
        applyRegex("</?[a-zA-Z][a-zA-Z0-9:-]*", color: NSColor.systemBlue, in: attr, code: code)
        // Attributes
        applyRegex("[a-zA-Z_:][-a-zA-Z0-9_:.]*(?=\\=)", color: NSColor.systemPurple, in: attr, code: code)
        // Comments
        applyRegex("<!--[\\s\\S]*?-->", color: NSColor.systemGreen, in: attr, code: code)
        // Attribute values (strings)
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor.systemRed, in: attr, code: code)
        
        return attr
    }
}
