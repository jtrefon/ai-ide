//
//  FileTreeAppearanceCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation
import AppKit

/// Handles appearance and styling for the file tree
@MainActor
final class FileTreeAppearanceCoordinator {
    private weak var outlineView: NSOutlineView?
    private var fontSize: Double = 13
    private var fontFamily: String = AppConstants.Editor.defaultFontFamily
    
    init(outlineView: NSOutlineView) {
        self.outlineView = outlineView
    }
    
    /// Updates the appearance of visible rows
    func applyAppearanceToVisibleRows() {
        guard let outlineView = outlineView else { return }
        
        let rowHeight = fontSize + 4
        outlineView.rowHeight = rowHeight
        
        for row in 0..<outlineView.numberOfRows {
            if let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView {
                if let textField = cellView.textField {
                    textField.font = NSFont(name: fontFamily, size: fontSize)
                    textField.textColor = NSColor.controlTextColor
                }
            }
        }
    }
    
    /// Updates the font settings
    func updateFont(fontSize: Double, fontFamily: String) {
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        applyAppearanceToVisibleRows()
    }
    
    /// Gets the current font settings
    var currentFont: (fontSize: Double, fontFamily: String) {
        return (fontSize: fontSize, fontFamily: fontFamily)
    }
}
