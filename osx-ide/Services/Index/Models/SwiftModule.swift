//
//  SwiftModule.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit

public final class SwiftModule: RegexLanguageModule, @unchecked Sendable {
    // Force re-indexing
    public init() {
        super.init(id: .swift, fileExtensions: ["swift"])
    }
    
    public override func highlight(_ code: String, font: NSFont) -> NSAttributedString {
        let base = makeBaseAttributedString(code: code, font: font)
        let attr = base.attributed

        applyDoubleQuotedStringHighlighting(color: NSColor.systemRed, in: attr, code: code)
        applyLineAndBlockCommentHighlighting(color: NSColor.systemGreen, in: attr, code: code)
        applyDecimalNumberHighlighting(color: NSColor.systemOrange, in: attr, code: code)
        
        let keywords = [
            "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
            "if", "else", "for", "while", "repeat", "switch", "case", "default", "break",
            "continue", "defer", "do", "catch", "throw", "throws", "rethrows", "try", "in",
            "where", "return", "as", "is", "nil", "true", "false", "init", "deinit",
            "subscript", "typealias", "associatedtype", "mutating", "nonmutating", "static",
            "final", "open", "public", "internal", "fileprivate", "private", "guard", "some",
            "any", "actor", "await", "async", "yield", "inout"
        ]
        let types = [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "Bool", "String", "Character",
            "Array", "Dictionary", "Set", "Optional", "Void", "Any", "AnyObject"
        ]
        
        highlightWholeWords(keywords, color: NSColor.systemBlue, in: attr, code: code)
        highlightWholeWords(types, color: NSColor.systemPurple, in: attr, code: code)
        
        return attr
    }
    
    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return SwiftParser.parse(content: content, resourceId: resourceId)
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .swift)
    }
}
