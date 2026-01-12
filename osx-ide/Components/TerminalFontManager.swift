//
//  TerminalFontManager.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation
import AppKit

/// Manages font configuration and resolution for terminal views
@MainActor
class TerminalFontManager {
    
    // MARK: - Font Properties
    
    private(set) var fontSize: CGFloat = 12
    private(set) var fontFamily: String = "SF Mono"
    private var foregroundColor: NSColor = .green
    private var backgroundColor: NSColor = .black
    
    // MARK: - Initialization
    
    init(size: CGFloat = 12, family: String = "SF Mono", foregroundColor: NSColor = .green, backgroundColor: NSColor = .black) {
        self.fontSize = size
        self.fontFamily = family
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
    
    // MARK: - Font Management
    
    /// Updates the font configuration
    func updateFont(size: Double, family: String) {
        self.fontSize = CGFloat(size)
        self.fontFamily = family
    }
    
    /// Updates the color configuration
    func updateColors(foreground: NSColor, background: NSColor) {
        self.foregroundColor = foreground
        self.backgroundColor = background
    }
    
    /// Resolves font with fallback to system monospace
    func resolveFont(size: CGFloat? = nil, family: String? = nil, weight: NSFont.Weight = .regular) -> NSFont {
        let actualSize = size ?? self.fontSize
        let actualFamily = family ?? self.fontFamily
        
        if let font = NSFont(name: actualFamily, size: actualSize) {
            return NSFontManager.shared.convert(font, toHaveTrait: weight == .bold ? .boldFontMask : .unboldFontMask)
        }
        return NSFont.monospacedSystemFont(ofSize: actualSize, weight: weight)
    }
    
    /// Creates default typing attributes for terminal text
    func createTypingAttributes(size: CGFloat? = nil, family: String? = nil) -> [NSAttributedString.Key: Any] {
        let font = resolveFont(size: size, family: family)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        
        return [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle
        ]
    }
    
    /// Applies font to existing text storage
    func applyFontToStorage(_ storage: NSTextStorage, size: CGFloat? = nil, family: String? = nil) {
        let font = resolveFont(size: size, family: family)
        
        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }
    
    /// Gets current font configuration
    var currentFont: (size: CGFloat, family: String) {
        return (size: fontSize, family: fontFamily)
    }
}
