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
        let base = makeBaseAttributedString(code: code, font: font)
        let attr = base.attributed
        let regexContext = RegexLanguageModule.RegexHighlightContext(attributedString: attr, code: code)

        // Tags and tag names
        applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: "</?[a-zA-Z][a-zA-Z0-9:-]*",
            color: NSColor.systemBlue,
            context: regexContext,
            captureGroup: nil
        ))
        // Attributes
        applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: "[a-zA-Z_:][-a-zA-Z0-9_:.]*(?=\\=)",
            color: NSColor.systemPurple,
            context: regexContext,
            captureGroup: nil
        ))
        // Comments
        applyRegex(RegexLanguageModule.RegexHighlightRequest(
            pattern: "<!--[\\s\\S]*?-->",
            color: NSColor.systemGreen,
            context: regexContext,
            captureGroup: nil
        ))
        // Attribute values (strings)
        applyDoubleQuotedStringHighlighting(color: NSColor.systemRed, in: attr, code: code)

        return attr
    }
}
