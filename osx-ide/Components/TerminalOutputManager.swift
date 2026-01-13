//
//  TerminalOutputManager.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation
import AppKit

/// Manages terminal output processing and display
@MainActor
class TerminalOutputManager {
    
    // MARK: - Properties
    
    private weak var terminalView: NSTextView?
    private let eventBus: EventBusProtocol
    private let ansiRenderer: TerminalANSIRenderer
    private let fontManager: TerminalFontManager
    
    // Cursor tracking
    private var currentLineStartLocation: Int = 0
    private var cursorColumn: Int = 0
    private var currentTextAttributes: [NSAttributedString.Key: Any] = [:]
    private var pendingEraseToEndOfLine: Bool = false
    
    // MARK: - Initialization
    
    init(
        terminalView: NSTextView?, 
        eventBus: EventBusProtocol, 
        ansiRenderer: TerminalANSIRenderer, 
        fontManager: TerminalFontManager
    ) {
        self.terminalView = terminalView
        self.eventBus = eventBus
        self.ansiRenderer = ansiRenderer
        self.fontManager = fontManager
    }
    
    // MARK: - Output Management
    
    /// Updates the terminal view reference
    func setTerminalView(_ view: NSTextView?) {
        self.terminalView = view
    }
    
    /// Appends output to the terminal with ANSI processing
    func appendOutput(_ text: String) {
        guard let terminalView = terminalView else { return }
        
        eventBus.publish(TerminalOutputProducedEvent(output: text))
        
        let shouldAutoscroll = isNearBottom(terminalView)
        applyTerminalOutput(text, to: terminalView)
        
        if shouldAutoscroll {
            let range = NSRange(location: terminalView.string.count, length: 0)
            terminalView.setSelectedRange(range)
            terminalView.scrollRangeToVisible(range)
        }
    }
    
    /// Applies terminal output with ANSI processing
    private func applyTerminalOutput(_ text: String, to terminalView: NSTextView) {
        let processedText = ansiRenderer.processANSIEscapeSequences(text)

        if processedText.string.isEmpty {
            return
        }

        let storage = terminalView.textStorage!
        let originalLength = storage.length

        storage.beginEditing()

        // Handle pending erase to end of line
        if pendingEraseToEndOfLine {
            if currentLineStartLocation > originalLength {
                pendingEraseToEndOfLine = false
            } else {
                let eraseRange = NSRange(
                    location: currentLineStartLocation, 
                    length: originalLength - currentLineStartLocation
                )
                if eraseRange.location + eraseRange.length <= storage.length {
                    storage.deleteCharacters(in: eraseRange)
                }
                pendingEraseToEndOfLine = false
            }
        }

        // Insert processed text
        storage.append(processedText)

        // Update cursor tracking
        if let newLineRange = processedText.string.range(of: "\n", options: .backwards) {
            currentLineStartLocation = originalLength +
                processedText.string.distance(
                    from: processedText.string.startIndex,
                    to: newLineRange.upperBound
                )
        }

        storage.endEditing()
    }
    
    /// Checks if terminal view is near bottom for autoscrolling
    private func isNearBottom(_ view: NSTextView) -> Bool {
        let visibleRect = view.visibleRect
        let contentRect = view.bounds
        return contentRect.maxY - visibleRect.maxY < 50
    }
    
    /// Clears all terminal content
    func clearAll() {
        guard let terminalView = terminalView else { return }
        
        terminalView.string = ""
        currentLineStartLocation = 0
        cursorColumn = 0
        currentTextAttributes = [:]
        pendingEraseToEndOfLine = false
    }
    
    /// Clears current line
    func clearLine() {
        guard let terminalView = terminalView else { return }
        
        let storage = terminalView.textStorage!
        let eraseRange = NSRange(
            location: currentLineStartLocation,
            length: storage.length - currentLineStartLocation
        )
        
        storage.beginEditing()
        storage.deleteCharacters(in: eraseRange)
        storage.endEditing()
        
        cursorColumn = 0
        pendingEraseToEndOfLine = false
    }
    
    /// Sets erase to end of line flag
    func setEraseToEndOfLine() {
        pendingEraseToEndOfLine = true
    }
    
    /// Updates cursor position
    func updateCursorPosition(column: Int) {
        cursorColumn = column
    }
    
    /// Gets current cursor position
    var currentCursorPosition: (lineStart: Int, column: Int) {
        return (lineStart: currentLineStartLocation, column: cursorColumn)
    }
}
