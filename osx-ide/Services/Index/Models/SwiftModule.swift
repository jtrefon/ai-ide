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
        let attr = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        
        attr.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)
        
        applyGenericHighlighting(in: attr, code: code)
        
        let keywords = [
            "class","struct","enum","protocol","extension","func","var","let","if","else","for","while","repeat","switch","case","default","break","continue","defer","do","catch","throw","throws","rethrows","try","in","where","return","as","is","nil","true","false","init","deinit","subscript","typealias","associatedtype","mutating","nonmutating","static","final","open","public","internal","fileprivate","private","guard","some","any","actor","await","async","yield","inout"
        ]
        let types = [
            "Int","Int8","Int16","Int32","Int64","UInt","UInt8","UInt16","UInt32","UInt64","Float","Double","Bool","String","Character","Array","Dictionary","Set","Optional","Void","Any","AnyObject"
        ]
        
        highlightWholeWords(keywords, color: NSColor.systemBlue, in: attr, code: code)
        highlightWholeWords(types, color: NSColor.systemPurple, in: attr, code: code)
        
        return attr
    }
    
    private func applyGenericHighlighting(in attr: NSMutableAttributedString, code: String) {
        // Strings
        applyRegex("\"(?:\\\\.|[^\"\\\\])*\"", color: NSColor.systemRed, in: attr, code: code)
        // Comments
        applyRegex("//.*", color: NSColor.systemGreen, in: attr, code: code)
        applyRegex("/\\*[\\s\\S]*?\\*/", color: NSColor.systemGreen, in: attr, code: code)
        // Numbers
        applyRegex("\\b\\d+(?:\\.\\d+)?\\b", color: NSColor.systemOrange, in: attr, code: code)
    }
    
    public override func parseSymbols(content: String, resourceId: String) -> [Symbol] {
        return SwiftParser.parse(content: content, resourceId: resourceId)
    }
    
    public override func format(_ code: String) -> String {
        return CodeFormatter.format(code, language: .swift)
    }
}
