//
//  TerminalBuffer.swift
//  osx-ide
//
//  Created by AI Assistant on 19/12/2025.
//

import Foundation
import AppKit

/// Terminal character with attributes
struct TerminalCharacter {
    var char: Character = " "
    var foregroundColor: ANSIColor = .default
    var backgroundColor: ANSIColor = .default
    var bold: Bool = false
    var dim: Bool = false
    var underline: Bool = false
    var blink: Bool = false
    var reverse: Bool = false
    var hidden: Bool = false
    
    init(char: Character = " ") {
        self.char = char
    }
    
    /// Get effective foreground color considering attributes
    func getEffectiveForegroundColor() -> NSColor {
        if reverse {
            return backgroundColor.nsColor
        } else if bold && foregroundColor != .default {
            return foregroundColor.brightNSColor
        } else {
            return foregroundColor.nsColor
        }
    }
    
    /// Get effective background color considering attributes
    func getEffectiveBackgroundColor() -> NSColor {
        if reverse {
            return foregroundColor.nsColor
        } else {
            return backgroundColor.nsColor
        }
    }
    
    /// Check if character should be visible
    func isVisible() -> Bool {
        return !hidden && char != "\0"
    }
}

/// Terminal screen buffer for efficient rendering
class TerminalBuffer {
    private var lines: [[TerminalCharacter]]
    private var cursorRow: Int = 0
    private var cursorColumn: Int = 0
    private var rows: Int
    private var columns: Int
    private var savedCursorRow: Int = 0
    private var savedCursorColumn: Int = 0
    private var currentAttributes = TerminalCharacter()
    
    /// Scrollback buffer for history
    private var scrollbackBuffer: [[TerminalCharacter]] = []
    private let maxScrollbackLines = 1000
    
    init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
        self.lines = Array(repeating: Array(repeating: TerminalCharacter(), count: columns), count: rows)
    }
    
    // MARK: - Buffer Operations
    
    func resize(rows: Int, columns: Int) {
        var newLines = Array(repeating: Array(repeating: TerminalCharacter(), count: columns), count: rows)
        
        // Copy existing content
        for i in 0..<min(self.rows, rows) {
            for j in 0..<min(self.columns, columns) {
                newLines[i][j] = lines[i][j]
            }
        }
        
        self.rows = rows
        self.columns = columns
        self.lines = newLines
        
        // Adjust cursor position if needed
        cursorRow = min(cursorRow, rows - 1)
        cursorColumn = min(cursorColumn, columns - 1)
    }
    
    func getLines() -> [[TerminalCharacter]] {
        return lines
    }
    
    func getCursorPosition() -> (row: Int, column: Int) {
        return (cursorRow, cursorColumn)
    }
    
    // MARK: - Character Writing
    
    func writeCharacter(_ char: Character) {
        if char == "\0" { return }
        
        var newChar = TerminalCharacter(char: char)
        newChar.foregroundColor = currentAttributes.foregroundColor
        newChar.backgroundColor = currentAttributes.backgroundColor
        newChar.bold = currentAttributes.bold
        newChar.dim = currentAttributes.dim
        newChar.underline = currentAttributes.underline
        newChar.blink = currentAttributes.blink
        newChar.reverse = currentAttributes.reverse
        newChar.hidden = currentAttributes.hidden
        
        lines[cursorRow][cursorColumn] = newChar
        
        advanceCursor()
    }
    
    private func advanceCursor() {
        cursorColumn += 1
        
        if cursorColumn >= columns {
            cursorColumn = 0
            newLine()
        }
    }
    
    // MARK: - Cursor Movement
    
    func setCursorPosition(row: Int, column: Int) {
        cursorRow = max(0, min(row, rows - 1))
        cursorColumn = max(0, min(column, columns - 1))
    }
    
    func moveCursorUp(_ count: Int) {
        cursorRow = max(0, cursorRow - count)
    }
    
    func moveCursorDown(_ count: Int) {
        cursorRow = min(rows - 1, cursorRow + count)
    }
    
    func moveCursorLeft(_ count: Int) {
        cursorColumn = max(0, cursorColumn - count)
    }
    
    func moveCursorRight(_ count: Int) {
        cursorColumn = min(columns - 1, cursorColumn + count)
    }
    
    func saveCursorPosition() {
        savedCursorRow = cursorRow
        savedCursorColumn = cursorColumn
    }
    
    func restoreCursorPosition() {
        cursorRow = savedCursorRow
        cursorColumn = savedCursorColumn
    }
    
    // MARK: - Line Operations
    
    func newLine() {
        // Add current line to scrollback if we're at the bottom
        if cursorRow >= rows - 1 {
            if scrollbackBuffer.count >= maxScrollbackLines {
                scrollbackBuffer.removeFirst()
            }
            scrollbackBuffer.append(lines[0])
        }
        
        // Scroll lines up
        for i in 0..<(rows - 1) {
            lines[i] = lines[i + 1]
        }
        
        // Clear last line
        lines[rows - 1] = Array(repeating: TerminalCharacter(), count: columns)
        
        // Move cursor to beginning of last line
        cursorRow = rows - 1
        cursorColumn = 0
    }
    
    func carriageReturn() {
        cursorColumn = 0
    }
    
    func tab() {
        let tabSize = 8
        let nextTabStop = ((cursorColumn / tabSize) + 1) * tabSize
        cursorColumn = min(nextTabStop, columns - 1)
    }
    
    func backspace() {
        if cursorColumn > 0 {
            cursorColumn -= 1
            lines[cursorRow][cursorColumn] = TerminalCharacter()
        }
    }
    
    // MARK: - Erase Operations
    
    func clearScreen() {
        lines = Array(repeating: Array(repeating: TerminalCharacter(), count: columns), count: rows)
        cursorRow = 0
        cursorColumn = 0
    }
    
    func eraseFromCursorToEnd() {
        // Clear from cursor to end of current line
        for col in cursorColumn..<columns {
            lines[cursorRow][col] = TerminalCharacter()
        }
        
        // Clear all lines below
        for row in (cursorRow + 1)..<rows {
            lines[row] = Array(repeating: TerminalCharacter(), count: columns)
        }
    }
    
    func eraseFromStartToCursor() {
        // Clear from beginning of current line to cursor
        for col in 0...cursorColumn {
            lines[cursorRow][col] = TerminalCharacter()
        }
        
        // Clear all lines above
        for row in 0..<cursorRow {
            lines[row] = Array(repeating: TerminalCharacter(), count: columns)
        }
    }
    
    func clearLine() {
        lines[cursorRow] = Array(repeating: TerminalCharacter(), count: columns)
    }
    
    func eraseLineFromCursorToEnd() {
        for col in cursorColumn..<columns {
            lines[cursorRow][col] = TerminalCharacter()
        }
    }
    
    func eraseLineFromStartToCursor() {
        for col in 0...cursorColumn {
            lines[cursorRow][col] = TerminalCharacter()
        }
    }
    
    // MARK: - Attribute Management
    
    func resetAttributes() {
        currentAttributes = TerminalCharacter()
    }
    
    func setBold(_ bold: Bool) {
        currentAttributes.bold = bold
    }
    
    func setDim(_ dim: Bool) {
        currentAttributes.dim = dim
    }
    
    func setUnderline(_ underline: Bool) {
        currentAttributes.underline = underline
    }
    
    func setBlink(_ blink: Bool) {
        currentAttributes.blink = blink
    }
    
    func setReverse(_ reverse: Bool) {
        currentAttributes.reverse = reverse
    }
    
    func setHidden(_ hidden: Bool) {
        currentAttributes.hidden = hidden
    }
    
    func setForegroundColor(color: ANSIColor) {
        currentAttributes.foregroundColor = color
    }
    
    func setBackgroundColor(color: ANSIColor) {
        currentAttributes.backgroundColor = color
    }
    
    func setForegroundColor256(colorIndex: Int) {
        // Convert 256 color index to ANSIColor or use extended color system
        // For now, map to basic colors
        if colorIndex < 16 {
            currentAttributes.foregroundColor = ANSIColor(rawValue: colorIndex % 8) ?? .default
        } else {
            // For simplicity, use basic colors for now
            currentAttributes.foregroundColor = ANSIColor(rawValue: colorIndex % 8) ?? .default
        }
    }
    
    func setBackgroundColor256(colorIndex: Int) {
        // Convert 256 color index to ANSIColor or use extended color system
        if colorIndex < 16 {
            currentAttributes.backgroundColor = ANSIColor(rawValue: colorIndex % 8) ?? .default
        } else {
            currentAttributes.backgroundColor = ANSIColor(rawValue: colorIndex % 8) ?? .default
        }
    }
    
    // MARK: - Scrollback Management
    
    func getScrollbackBuffer() -> [[TerminalCharacter]] {
        return scrollbackBuffer
    }
    
    func clearScrollback() {
        scrollbackBuffer.removeAll()
    }
}
