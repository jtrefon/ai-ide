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
        let base = makeBaseAttributedString(code: code, font: font)
        let attr = base.attributed

        DefaultCSSHighlighter.applyAll(in: attr, code: code)

        return attr
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .css)
    }
}
