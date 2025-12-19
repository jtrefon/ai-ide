//
//  TerminalEmulator.swift
//  osx-ide
//
//  Created by AI Assistant on 19/12/2025.
//

import Foundation
import AppKit

/// ANSI escape sequence parser and terminal emulator
class TerminalEmulator {
    private var buffer: TerminalBuffer
    private var parseState = ParseState.normal
    private var escapeSequence = ""
    private var parameters: [Int] = []
    
    /// Callback for when the screen content changes
    var onScreenUpdate: (() -> Void)?
    
    /// Callback for when cursor position changes
    var onCursorUpdate: (() -> Void)?
    
    init(rows: Int, columns: Int) {
        self.buffer = TerminalBuffer(rows: rows, columns: columns)
    }
    
    /// Resize the terminal
    func resize(rows: Int, columns: Int) {
        buffer.resize(rows: rows, columns: columns)
        onScreenUpdate?()
    }
    
    /// Get the current screen content
    func getScreenContent() -> [[TerminalCharacter]] {
        return buffer.getLines()
    }
    
    /// Get current cursor position
    func getCursorPosition() -> (row: Int, column: Int) {
        return buffer.getCursorPosition()
    }
    
    /// Process incoming data from PTY
    func processData(_ data: Data) {
        let string = String(decoding: data, as: UTF8.self)
        
        for char in string {
            processCharacter(char)
        }
        
        onScreenUpdate?()
    }
    
    // MARK: - Private Methods
    
    private func processCharacter(_ char: Character) {
        switch parseState {
        case .normal:
            if char == "\u{1B}" { // ESC
                parseState = .escape
                escapeSequence = String(char)
            } else if char == "\n" {
                buffer.newLine()
            } else if char == "\r" {
                buffer.carriageReturn()
            } else if char == "\t" {
                buffer.tab()
            } else if char == "\u{7}" { // BEL
                // Bell character - could play sound
            } else if char == "\u{8}" { // Backspace
                buffer.backspace()
            } else {
                buffer.writeCharacter(char)
            }
            
        case .escape:
            escapeSequence += String(char)
            
            if char == "[" {
                parseState = .csi
                parameters = [0]
            } else if char == "]" {
                parseState = .osc
            } else if char == "(" || char == ")" {
                parseState = .charset
            } else {
                // Other escape sequences
                parseState = .normal
            }
            
        case .csi: // Control Sequence Introducer
            if char.isNumber {
                escapeSequence += String(char)
                if parameters.isEmpty {
                    parameters = [0]
                }
                // Build parameter
                let lastParam = parameters[parameters.count - 1]
                parameters[parameters.count - 1] = lastParam * 10 + Int(String(char))!
            } else if char == ";" {
                parameters.append(0)
            } else if char.isLetter {
                // End of CSI sequence
                processCSISequence(char)
                parseState = .normal
                escapeSequence = ""
            } else {
                escapeSequence += String(char)
            }
            
        case .osc: // Operating System Command
            if char == "\u{7}" || (char == "\\" && escapeSequence.count > 1) {
                // End of OSC sequence
                processOSCSequence()
                parseState = .normal
                escapeSequence = ""
            } else {
                escapeSequence += String(char)
            }
            
        case .charset:
            parseState = .normal
            escapeSequence = ""
        }
    }
    
    private func processCSISequence(_ finalChar: Character) {
        // Default parameters if none provided
        if parameters.isEmpty {
            parameters = [0]
        }
        
        switch finalChar {
        case "A": // Cursor Up
            let count = parameters[0] == 0 ? 1 : parameters[0]
            buffer.moveCursorUp(count)
            
        case "B": // Cursor Down
            let count = parameters[0] == 0 ? 1 : parameters[0]
            buffer.moveCursorDown(count)
            
        case "C": // Cursor Forward (Right)
            let count = parameters[0] == 0 ? 1 : parameters[0]
            buffer.moveCursorRight(count)
            
        case "D": // Cursor Backward (Left)
            let count = parameters[0] == 0 ? 1 : parameters[0]
            buffer.moveCursorLeft(count)
            
        case "H", "f": // Cursor Position
            let row = parameters.count > 0 ? (parameters[0] == 0 ? 1 : parameters[0]) - 1 : 0
            let col = parameters.count > 1 ? (parameters[1] == 0 ? 1 : parameters[1]) - 1 : 0
            buffer.setCursorPosition(row: row, column: col)
            
        case "J": // Erase in Display
            let mode = parameters[0]
            switch mode {
            case 0: buffer.eraseFromCursorToEnd()
            case 1: buffer.eraseFromStartToCursor()
            case 2: buffer.clearScreen()
            default: break
            }
            
        case "K": // Erase in Line
            let mode = parameters[0]
            switch mode {
            case 0: buffer.eraseLineFromCursorToEnd()
            case 1: buffer.eraseLineFromStartToCursor()
            case 2: buffer.clearLine()
            default: break
            }
            
        case "m": // Select Graphic Rendition (SGR) - Colors and formatting
            processSGRSequence(parameters)
            
        case "s": // Save Cursor Position
            buffer.saveCursorPosition()
            
        case "u": // Restore Cursor Position
            buffer.restoreCursorPosition()
            
        case "l": // Reset Mode
            // Handle various mode resets
            break
            
        case "h": // Set Mode
            // Handle various mode settings
            break
            
        default:
            // Unhandled CSI sequence
            break
        }
        
        onCursorUpdate?()
    }
    
    private func processSGRSequence(_ params: [Int]) {
        for param in params {
            switch param {
            case 0: // Reset
                buffer.resetAttributes()
            case 1: // Bold
                buffer.setBold(true)
            case 2: // Dim
                buffer.setDim(true)
            case 4: // Underline
                buffer.setUnderline(true)
            case 5, 6: // Blink
                buffer.setBlink(true)
            case 7: // Reverse
                buffer.setReverse(true)
            case 8: // Hidden
                buffer.setHidden(true)
            case 22: // Normal intensity
                buffer.setBold(false)
                buffer.setDim(false)
            case 24: // Not underline
                buffer.setUnderline(false)
            case 25: // Not blink
                buffer.setBlink(false)
            case 27: // Not reverse
                buffer.setReverse(false)
            case 28: // Not hidden
                buffer.setHidden(false)
                
            case 30...37: // Foreground colors
                buffer.setForegroundColor(color: ANSIColor(rawValue: param - 30) ?? .default)
            case 38: // 256/true color foreground
                if params.count >= 3 && params[1] == 5 {
                    buffer.setForegroundColor256(colorIndex: params[2])
                }
            case 39: // Default foreground
                buffer.setForegroundColor(color: .default)
                
            case 40...47: // Background colors
                buffer.setBackgroundColor(color: ANSIColor(rawValue: param - 40) ?? .default)
            case 48: // 256/true color background
                if params.count >= 3 && params[1] == 5 {
                    buffer.setBackgroundColor256(colorIndex: params[2])
                }
            case 49: // Default background
                buffer.setBackgroundColor(color: .default)
                
            case 90...97: // Bright foreground colors
                buffer.setForegroundColor(color: ANSIColor(rawValue: param - 90 + 8) ?? .default)
            case 100...107: // Bright background colors
                buffer.setBackgroundColor(color: ANSIColor(rawValue: param - 100 + 8) ?? .default)
                
            default:
                break
            }
        }
    }
    
    private func processOSCSequence() {
        // Handle operating system commands like setting window title
        // For now, just ignore
    }
}

// MARK: - Parse States

private enum ParseState {
    case normal
    case escape
    case csi     // Control Sequence Introducer
    case osc     // Operating System Command
    case charset // Character set selection
}

// MARK: - ANSI Colors

enum ANSIColor: Int {
    case black = 0
    case red = 1
    case green = 2
    case yellow = 3
    case blue = 4
    case magenta = 5
    case cyan = 6
    case white = 7
    case `default` = 9
    
    var nsColor: NSColor {
        switch self {
        case .black: return NSColor.black
        case .red: return NSColor.red
        case .green: return NSColor.green
        case .yellow: return NSColor.yellow
        case .blue: return NSColor.blue
        case .magenta: return NSColor.magenta
        case .cyan: return NSColor.cyan
        case .white: return NSColor.white
        case .default: return NSColor.textColor
        }
    }
    
    var brightNSColor: NSColor {
        switch self {
        case .black: return NSColor.darkGray
        case .red: return NSColor.systemRed
        case .green: return NSColor.systemGreen
        case .yellow: return NSColor.systemYellow
        case .blue: return NSColor.systemBlue
        case .magenta: return NSColor.systemPurple
        case .cyan: return NSColor.systemTeal
        case .white: return NSColor.white
        case .default: return NSColor.textColor
        }
    }
}

