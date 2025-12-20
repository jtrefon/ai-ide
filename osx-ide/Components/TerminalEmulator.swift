//
//  TerminalEmulator.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation
import AppKit

/// Terminal emulator that handles escape sequences and renders to NSTextView
@MainActor
class TerminalEmulator: NSObject {
    private weak var textView: NSTextView?
    private var ptyWrapper: PTYWrapper?
    private var cursorPosition: (row: Int, col: Int) = (0, 0)
    private var terminalSize: (rows: Int, cols: Int) = (24, 80)
    
    // Terminal state
    private var currentAttributes: [NSAttributedString.Key: Any] = [:]
    private var buffer: [[TerminalCharacter]] = []
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        setupTextView()
        initializeBuffer()
    }
    
    /// Connect to PTY wrapper
    func connect(ptyWrapper: PTYWrapper) {
        self.ptyWrapper = ptyWrapper
        
        // Setup input handling
        setupInputHandling()
        
        // Set initial window size
        updateTerminalSize()
    }
    
    /// Setup text view properties
    private func setupTextView() {
        guard let textView = textView else { return }
        
        textView.delegate = self
        currentAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.green
        ]
    }
    
    /// Initialize terminal buffer
    private func initializeBuffer() {
        buffer = Array(repeating: Array(repeating: TerminalCharacter(" ", attributes: currentAttributes), 
                                      count: terminalSize.cols), 
                      count: terminalSize.rows)
    }
    
    /// Setup input handling for text view
    private func setupInputHandling() {
        // This will be handled by key events in the delegate
    }
    
    /// Handle output from PTY
    func handleOutput(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.processOutput(string)
        }
    }
    
    /// Process terminal output and handle escape sequences
    private func processOutput(_ output: String) {
        var i = output.startIndex
        
        while i < output.endIndex {
            let char = output[i]
            
            if char == "\u{1B}" {
                // Escape sequence
                i = processEscapeSequence(output, from: i)
            } else if char == "\n" {
                // Newline
                newline()
                i = output.index(after: i)
            } else if char == "\r" {
                // Carriage return
                carriageReturn()
                i = output.index(after: i)
            } else if char == "\t" {
                // Tab
                tab()
                i = output.index(after: i)
            } else if char == "\u{7F}" {
                // Backspace
                backspace()
                i = output.index(after: i)
            } else {
                // Regular character
                insertCharacter(String(char))
                i = output.index(after: i)
            }
        }
        
        updateDisplay()
    }
    
    /// Process escape sequences
    private func processEscapeSequence(_ string: String, from start: String.Index) -> String.Index {
        var i = string.index(after: start)
        
        guard i < string.endIndex else { return i }
        
        let nextChar = string[i]
        
        if nextChar == "[" {
            // CSI sequence
            i = string.index(after: i)
            return processCSISequence(string, from: i)
        } else {
            // Other escape sequences
            i = string.index(after: i)
            return i
        }
    }
    
    /// Process CSI (Control Sequence Introducer) sequences
    private func processCSISequence(_ string: String, from start: String.Index) -> String.Index {
        var i = start
        var parameters: [Int] = []
        var currentParam = ""
        
        // Parse parameters
        while i < string.endIndex {
            let char = string[i]
            
            if char.isNumber {
                currentParam.append(char)
            } else if char == ";" {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                    currentParam = ""
                }
            } else if char >= "A" && char <= "Z" || char >= "a" && char <= "z" {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                }
                
                // Handle the command
                handleCSICommand(char, parameters: parameters)
                return string.index(after: i)
            }
            
            i = string.index(after: i)
        }
        
        return i
    }
    
    /// Handle CSI commands
    private func handleCSICommand(_ command: Character, parameters: [Int]) {
        switch command {
        case "m":
            // SGR (Select Graphic Rendition)
            handleSGR(parameters)
        case "H":
            // Cursor position
            let row = (parameters.first ?? 1) - 1
            let col = (parameters.count > 1 ? parameters[1] : 1) - 1
            setCursorPosition(row: max(0, row), col: max(0, col))
        case "J":
            // Erase in display
            eraseInDisplay(parameters.first ?? 0)
        case "K":
            // Erase in line
            eraseInLine(parameters.first ?? 0)
        case "A":
            // Cursor up
            moveCursorUp(parameters.first ?? 1)
        case "B":
            // Cursor down
            moveCursorDown(parameters.first ?? 1)
        case "C":
            // Cursor forward
            moveCursorForward(parameters.first ?? 1)
        case "D":
            // Cursor backward
            moveCursorBackward(parameters.first ?? 1)
        default:
            break
        }
    }
    
    /// Handle SGR (Select Graphic Rendition) parameters
    private func handleSGR(_ parameters: [Int]) {
        for param in parameters.isEmpty ? [0] : parameters {
            switch param {
            case 0:
                // Reset
                currentAttributes = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.green
                ]
            case 30...37:
                // Foreground colors
                currentAttributes[.foregroundColor] = colorForCode(param)
            case 40...47:
                // Background colors
                currentAttributes[.backgroundColor] = colorForCode(param - 10)
            default:
                break
            }
        }
    }
    
    /// Get color for ANSI color code
    private func colorForCode(_ code: Int) -> NSColor {
        switch code {
        case 30, 40: return .black
        case 31, 41: return .red
        case 32, 42: return .green
        case 33, 43: return .yellow
        case 34, 44: return .blue
        case 35, 45: return .magenta
        case 36, 46: return .cyan
        case 37, 47: return .white
        default: return .green
        }
    }
    
    /// Insert character at cursor position
    private func insertCharacter(_ char: String) {
        guard cursorPosition.row < buffer.count && cursorPosition.col < buffer[cursorPosition.row].count else {
            return
        }
        
        buffer[cursorPosition.row][cursorPosition.col] = TerminalCharacter(char, attributes: currentAttributes)
        moveCursorForward(1)
    }
    
    /// Move cursor forward
    private func moveCursorForward(_ count: Int) {
        cursorPosition.col = min(cursorPosition.col + count, terminalSize.cols - 1)
    }
    
    /// Move cursor backward
    private func moveCursorBackward(_ count: Int) {
        cursorPosition.col = max(cursorPosition.col - count, 0)
    }
    
    /// Move cursor up
    private func moveCursorUp(_ count: Int) {
        cursorPosition.row = max(cursorPosition.row - count, 0)
    }
    
    /// Move cursor down
    private func moveCursorDown(_ count: Int) {
        cursorPosition.row = min(cursorPosition.row + count, terminalSize.rows - 1)
    }
    
    /// Set cursor position
    private func setCursorPosition(row: Int, col: Int) {
        cursorPosition.row = max(0, min(row, terminalSize.rows - 1))
        cursorPosition.col = max(0, min(col, terminalSize.cols - 1))
    }
    
    /// Newline
    private func newline() {
        cursorPosition.row += 1
        if cursorPosition.row >= terminalSize.rows {
            scrollUp()
            cursorPosition.row = terminalSize.rows - 1
        }
        cursorPosition.col = 0
    }
    
    /// Carriage return
    private func carriageReturn() {
        cursorPosition.col = 0
    }
    
    /// Tab
    private func tab() {
        cursorPosition.col = ((cursorPosition.col / 8) + 1) * 8
        if cursorPosition.col >= terminalSize.cols {
            newline()
        }
    }
    
    /// Backspace
    private func backspace() {
        moveCursorBackward(1)
        insertCharacter(" ")
        moveCursorBackward(1)
    }
    
    /// Scroll up
    private func scrollUp() {
        buffer.removeFirst()
        buffer.append(Array(repeating: TerminalCharacter(" ", attributes: currentAttributes), 
                           count: terminalSize.cols))
    }
    
    /// Erase in display
    private func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            // Erase from cursor to end of screen
            for row in cursorPosition.row..<terminalSize.rows {
                for col in (row == cursorPosition.row ? cursorPosition.col : 0)..<terminalSize.cols {
                    buffer[row][col] = TerminalCharacter(" ", attributes: currentAttributes)
                }
            }
        case 1:
            // Erase from beginning to cursor
            for row in 0...cursorPosition.row {
                for col in 0..<(row == cursorPosition.row ? cursorPosition.col + 1 : terminalSize.cols) {
                    buffer[row][col] = TerminalCharacter(" ", attributes: currentAttributes)
                }
            }
        case 2:
            // Erase entire screen
            initializeBuffer()
        default:
            break
        }
    }
    
    /// Erase in line
    private func eraseInLine(_ mode: Int) {
        switch mode {
        case 0:
            // Erase from cursor to end of line
            for col in cursorPosition.col..<terminalSize.cols {
                buffer[cursorPosition.row][col] = TerminalCharacter(" ", attributes: currentAttributes)
            }
        case 1:
            // Erase from beginning to cursor
            for col in 0...cursorPosition.col {
                buffer[cursorPosition.row][col] = TerminalCharacter(" ", attributes: currentAttributes)
            }
        case 2:
            // Erase entire line
            for col in 0..<terminalSize.cols {
                buffer[cursorPosition.row][col] = TerminalCharacter(" ", attributes: currentAttributes)
            }
        default:
            break
        }
    }
    
    /// Update display
    private func updateDisplay() {
        guard let textView = textView else { return }
        
        let attributedString = NSMutableAttributedString()
        
        for row in buffer {
            for char in row {
                attributedString.append(NSAttributedString(string: char.character, attributes: char.attributes))
            }
            attributedString.append(NSAttributedString(string: "\n"))
        }
        
        textView.textStorage?.setAttributedString(attributedString)
        
        // Scroll to bottom
        let range = NSRange(location: textView.string.count, length: 0)
        textView.scrollRangeToVisible(range)
    }
    
    /// Update terminal size
    private func updateTerminalSize() {
        guard let textView = textView else { return }
        
        let size = textView.bounds.size
        let charWidth: CGFloat = 7.2 // Approximate width of monospace character
        let charHeight: CGFloat = 14.0 // Approximate height of monospace character
        
        let cols = Int(size.width / charWidth)
        let rows = Int(size.height / charHeight)
        
        terminalSize = (rows: max(24, rows), cols: max(80, cols))
        
        // Update PTY window size
        if let ptyWrapper = ptyWrapper {
            var ws = winsize()
            ws.ws_row = UInt16(terminalSize.rows)
            ws.ws_col = UInt16(terminalSize.cols)
            ptyWrapper.setWindowSize(ws)
        }
        
        // Reinitialize buffer with new size
        initializeBuffer()
    }
    
    /// Send input to PTY
    private func sendInput(_ data: Data) {
        ptyWrapper?.writeInput(data)
    }
}

/// Terminal character with attributes
struct TerminalCharacter {
    let character: String
    let attributes: [NSAttributedString.Key: Any]
    
    init(_ character: String, attributes: [NSAttributedString.Key: Any]) {
        self.character = character
        self.attributes = attributes
    }
}

/// Extension for NSTextViewDelegate
extension TerminalEmulator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if let replacementString = replacementString {
            let data = replacementString.data(using: .utf8) ?? Data()
            sendInput(data)
        }
        return false // Don't let text view handle the input directly
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendInput("\n".data(using: .utf8) ?? Data())
            return true
        } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            sendInput("\u{7F}".data(using: .utf8) ?? Data())
            return true
        } else if commandSelector == #selector(NSResponder.deleteForward(_:)) {
            sendInput("\u{1B}[3~".data(using: .utf8) ?? Data())
            return true
        }
        return false
    }
}
