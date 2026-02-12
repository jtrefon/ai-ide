import AppKit
import Foundation

extension NativeTerminalEmbedder {
    func appendOutput(_ text: String) {
        guard !isCleaningUp, let terminalView = terminalView else { return }

        eventBus.publish(TerminalOutputProducedEvent(output: text))

        let shouldAutoscroll = isNearBottom(terminalView)
        applyTerminalOutput(text, to: terminalView)

        if shouldAutoscroll {
            let range = NSRange(location: terminalView.string.count, length: 0)
            terminalView.setSelectedRange(range)
            terminalView.scrollRangeToVisible(range)
        }
    }

    func isNearBottom(_ terminalView: NSTextView) -> Bool {
        guard let scrollView = terminalView.enclosingScrollView else { return true }
        let contentHeight = scrollView.contentView.bounds.height
        let maxY = scrollView.contentView.bounds.maxY
        let docHeight = scrollView.documentView?.bounds.height ?? 0
        if contentHeight <= 0 { return true }
        return (docHeight - maxY) < max(40, contentHeight * 0.15)
    }

    func applyTerminalOutput(_ text: String, to terminalView: NSTextView) {
        // DEBUG: Log raw output
        print("[DEBUG applyTerminalOutput] Raw output text (escaped): \(text.debugDescription)")
        print("[DEBUG applyTerminalOutput] Newline count in output: \(text.filter { $0 == "\n" }.count)")
        print("[DEBUG applyTerminalOutput] Carriage return count in output: \(text.filter { $0 == "\r" }.count)")
        
        // Use the screen buffer if available
        if let buffer = screenBuffer {
            applyTerminalOutputToBuffer(text, buffer: buffer)
            // Render the buffer to the text view
            screenRenderer?.render(buffer, fontSize: fontSize, fontFamily: fontFamily)
            
            // Synchronize the text view's cursor position with the buffer's cursor position
            if let renderer = screenRenderer {
                let cursorPos = renderer.cursorTextPosition(in: buffer)
                terminalView.setSelectedRange(NSRange(location: cursorPos, length: 0))
            }
            
            // DEBUG: Log cursor position after rendering
            print("[DEBUG applyTerminalOutput] After render - buffer cursorRow: \(buffer.cursorRow), cursorColumn: \(buffer.cursorColumn)")
            print("[DEBUG applyTerminalOutput] After render - textView.selectedRange: \(terminalView.selectedRange())")
            return
        }
        
        // Fallback to old behavior if buffer not initialized
        guard let textStorage = terminalView.textStorage else {
            terminalView.string += processANSIEscapeSequences(text).string
            currentLineStartLocation = terminalView.string.count
            cursorColumn = 0
            currentTextAttributes = terminalView.typingAttributes
            pendingEraseToEndOfLine = false
            return
        }

        if currentTextAttributes.isEmpty {
            currentTextAttributes = terminalView.typingAttributes
        }

        applyTerminalOutputCharacters(text, into: textStorage)
    }
    
    /// Process output through the screen buffer
    func applyTerminalOutputToBuffer(_ text: String, buffer: TerminalScreenBuffer) {
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            
            // Handle ANSI escape sequences
            if ch == "\u{1B}" {
                if let newIndex = consumeBufferANSISequence(text, at: index, buffer: buffer) {
                    index = newIndex
                    continue
                }
            }
            
            // Handle control characters
            switch ch {
            case "\n":
                buffer.newline()
            case "\r":
                buffer.carriageReturn()
            case "\t":
                buffer.tab()
            case "\u{08}", "\u{7F}":  // Backspace or DEL
                buffer.backspace()
            default:
                // Skip other control characters
                let scalarValue = ch.unicodeScalars.first?.value ?? 0
                let isControl = scalarValue < 32
                if ch.isASCII && !isControl {
                    buffer.putCharacter(ch)
                }
            }
            
            index = text.index(after: index)
        }
    }
    
    /// Process ANSI sequence for buffer mode
    func consumeBufferANSISequence(_ text: String, at index: String.Index, buffer: TerminalScreenBuffer) -> String.Index? {
        guard index < text.endIndex, text[index] == "\u{1B}" else { return nil }
        
        var index = text.index(after: index)
        guard index < text.endIndex else { return index }
        
        // CSI sequence: ESC [
        if text[index] == "[" {
            index = text.index(after: index)
            return parseBufferCSISequence(text, from: index, buffer: buffer)
        }
        
        // OSC sequence: ESC ]
        if text[index] == "]" {
            return consumeBufferOSCSequence(text, from: index)
        }
        
        // Unknown sequence, skip the character after ESC
        return text.index(after: index)
    }
    
    /// Parse CSI sequence for buffer mode
    func parseBufferCSISequence(_ text: String, from start: String.Index, buffer: TerminalScreenBuffer) -> String.Index {
        var index = start
        var parameters: [Int] = []
        var currentParam = ""
        
        while index < text.endIndex {
            let char = text[index]
            
            if char.isNumber {
                currentParam.append(char)
                index = text.index(after: index)
                continue
            }
            
            if char == ";" {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                    currentParam = ""
                }
                index = text.index(after: index)
                continue
            }
            
            // Check if this is a CSI final byte
            let isFinal = (char >= "A" && char <= "Z") || (char >= "a" && char <= "z")
            if isFinal {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                }
                handleBufferCSIFinalCharacter(char, parameters: parameters, buffer: buffer)
                return text.index(after: index)
            }
            
            index = text.index(after: index)
        }
        
        return index
    }
    
    /// Handle CSI final character for buffer mode
    func handleBufferCSIFinalCharacter(_ finalChar: Character, parameters: [Int], buffer: TerminalScreenBuffer) {
        switch finalChar {
        case "m":
            handleBufferSGR(parameters, buffer: buffer)
        case "H", "f":
            handleBufferCursorPosition(parameters: parameters, buffer: buffer)
        case "A":
            handleBufferCursorUp(parameters: parameters, buffer: buffer)
        case "B":
            handleBufferCursorDown(parameters: parameters, buffer: buffer)
        case "C":
            handleBufferCursorForward(parameters: parameters, buffer: buffer)
        case "D":
            handleBufferCursorBackward(parameters: parameters, buffer: buffer)
        case "G":
            handleBufferCursorHorizontalAbsolute(parameters: parameters, buffer: buffer)
        case "J":
            handleBufferEraseInDisplay(parameters: parameters, buffer: buffer)
        case "K":
            handleBufferEraseInLine(parameters: parameters, buffer: buffer)
        case "P":
            handleBufferDeleteCharacters(parameters: parameters, buffer: buffer)
        case "X":
            handleBufferEraseCharacters(parameters: parameters, buffer: buffer)
        case "r":
            handleBufferSetScrollRegion(parameters: parameters, buffer: buffer)
        default:
            break
        }
    }
    
    /// Handle SGR (Select Graphic Rendition) for buffer
    func handleBufferSGR(_ parameters: [Int], buffer: TerminalScreenBuffer) {
        for param in parameters.isEmpty ? [0] : parameters {
            switch param {
            case 0:
                // Reset all attributes
                buffer.currentForegroundColor = .green
                buffer.currentBackgroundColor = .black
                buffer.currentBold = false
                buffer.currentItalic = false
                buffer.currentUnderlined = false
            case 1:
                buffer.currentBold = true
            case 3:
                buffer.currentItalic = true
            case 4:
                buffer.currentUnderlined = true
            case 22:
                buffer.currentBold = false
            case 23:
                buffer.currentItalic = false
            case 24:
                buffer.currentUnderlined = false
            case 30...37:
                buffer.currentForegroundColor = ansiColor(param - 30)
            case 39:
                buffer.currentForegroundColor = .green
            case 40...47:
                buffer.currentBackgroundColor = ansiColor(param - 40)
            case 49:
                buffer.currentBackgroundColor = .black
            case 90...97:
                buffer.currentForegroundColor = ansiBrightColor(param - 90)
            case 100...107:
                buffer.currentBackgroundColor = ansiBrightColor(param - 100)
            default:
                break
            }
        }
    }
    
    /// Handle cursor positioning (CUP) - ESC [ row ; col H
    func handleBufferCursorPosition(parameters: [Int], buffer: TerminalScreenBuffer) {
        let row = max(1, parameters.first ?? 1) - 1  // Convert to 0-indexed
        let col = max(1, parameters.dropFirst().first ?? 1) - 1  // Convert to 0-indexed
        buffer.moveCursor(row: row, column: col)
    }
    
    /// Handle cursor up (CUU) - ESC [ n A
    func handleBufferCursorUp(parameters: [Int], buffer: TerminalScreenBuffer) {
        let rows = max(1, parameters.first ?? 1)
        buffer.moveCursorRelative(rowDelta: -rows, columnDelta: 0)
    }
    
    /// Handle cursor down (CUD) - ESC [ n B
    func handleBufferCursorDown(parameters: [Int], buffer: TerminalScreenBuffer) {
        let rows = max(1, parameters.first ?? 1)
        buffer.moveCursorRelative(rowDelta: rows, columnDelta: 0)
    }
    
    /// Handle cursor forward (CUF) - ESC [ n C
    func handleBufferCursorForward(parameters: [Int], buffer: TerminalScreenBuffer) {
        let cols = max(1, parameters.first ?? 1)
        buffer.moveCursorRelative(rowDelta: 0, columnDelta: cols)
    }
    
    /// Handle cursor backward (CUB) - ESC [ n D
    func handleBufferCursorBackward(parameters: [Int], buffer: TerminalScreenBuffer) {
        let cols = max(1, parameters.first ?? 1)
        buffer.moveCursorRelative(rowDelta: 0, columnDelta: -cols)
    }
    
    /// Handle cursor horizontal absolute (CHA) - ESC [ n G
    func handleBufferCursorHorizontalAbsolute(parameters: [Int], buffer: TerminalScreenBuffer) {
        let col = max(1, parameters.first ?? 1) - 1  // Convert to 0-indexed
        buffer.moveCursor(row: buffer.cursorRow, column: col)
    }
    
    /// Handle erase in display (ED) - ESC [ n J
    func handleBufferEraseInDisplay(parameters: [Int], buffer: TerminalScreenBuffer) {
        let mode = parameters.first ?? 0
        switch mode {
        case 0:
            buffer.eraseToEndOfScreen()
        case 1:
            buffer.eraseToStartOfScreen()
        case 2, 3:
            buffer.eraseScreen()
        default:
            break
        }
    }
    
    /// Handle erase in line (EL) - ESC [ n K
    func handleBufferEraseInLine(parameters: [Int], buffer: TerminalScreenBuffer) {
        let mode = parameters.first ?? 0
        switch mode {
        case 0:
            buffer.eraseToEndOfLine()
        case 1:
            buffer.eraseToStartOfLine()
        case 2:
            buffer.eraseLine()
        default:
            break
        }
    }
    
    /// Handle delete characters (DCH) - ESC [ n P
    func handleBufferDeleteCharacters(parameters: [Int], buffer: TerminalScreenBuffer) {
        // For simplicity, we erase characters at cursor position
        // A full implementation would shift the rest of the line left
        let count = max(1, parameters.first ?? 1)
        for _ in 0..<count {
            if buffer.cursorColumn < buffer.columns {
                buffer.eraseToEndOfLine()
            }
        }
    }
    
    /// Handle erase characters (ECH) - ESC [ n X
    func handleBufferEraseCharacters(parameters: [Int], buffer: TerminalScreenBuffer) {
        let count = max(1, parameters.first ?? 1)
        buffer.eraseCharacters(count)
    }
    
    /// Handle set scroll region (DECSTBM) - ESC [ top ; bottom r
    func handleBufferSetScrollRegion(parameters: [Int], buffer: TerminalScreenBuffer) {
        // For now, we just acknowledge but don't fully implement scroll regions
        // The buffer already handles scrolling naturally
        _ = parameters
    }
    
    /// Consume OSC sequence for buffer mode (skip it)
    func consumeBufferOSCSequence(_ text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex {
            if text[index] == "\u{07}" {
                return text.index(after: index)
            }
            
            if text[index] == "\u{1B}",
               index < text.index(before: text.endIndex),
               text[text.index(after: index)] == "\\" {
                return text.index(after: text.index(after: index))
            }
            
            index = text.index(after: index)
        }
        
        return index
    }

    // MARK: - Legacy Methods (for fallback)
    
    func applyTerminalOutputCharacters(_ text: String, into textStorage: NSTextStorage) {
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]

            if let newIndex = consumeEscapeSequenceIfPresent(text, at: index) {
                index = newIndex
                continue
            }

            if let newIndex = consumeLineBreakIfPresent(text, at: index, into: textStorage) {
                index = newIndex
                continue
            }

            if let newIndex = consumeEditingControlIfPresent(text, at: index, into: textStorage) {
                index = newIndex
                continue
            }

            if consumeIgnoredControlIfPresent(ch) {
                index = text.index(after: index)
                continue
            }

            if pendingEraseToEndOfLine {
                eraseToEndOfLine(in: textStorage)
                pendingEraseToEndOfLine = false
            }

            putCharacter(String(ch), into: textStorage)
            index = text.index(after: index)
        }
    }

    func consumeEscapeSequenceIfPresent(_ text: String, at index: String.Index) -> String.Index? {
        guard text[index] == "\u{1B}" else { return nil }
        guard let parsed = parseANSISequence(text, from: index) else { return nil }
        if !parsed.shouldSkip {
            currentTextAttributes.merge(parsed.attributes) { _, new in new }
        }
        return parsed.newIndex
    }

    func consumeLineBreakIfPresent(
        _ text: String,
        at index: String.Index,
        into textStorage: NSTextStorage
    ) -> String.Index? {
        let ch = text[index]
        if ch == "\n" {
            appendNewline(into: textStorage)
            return text.index(after: index)
        }

        if ch == "\r" {
            return handleCarriageReturn(in: text, at: index, into: textStorage)
        }

        return nil
    }

    func consumeEditingControlIfPresent(
        _ text: String,
        at index: String.Index,
        into textStorage: NSTextStorage
    ) -> String.Index? {
        let ch = text[index]
        if ch == "\u{08}" || ch == "\u{7F}" {
            handleBackspace()
            return text.index(after: index)
        }

        if ch == "\t" {
            appendTab(into: textStorage)
            return text.index(after: index)
        }

        return nil
    }

    func consumeIgnoredControlIfPresent(_ ch: Character) -> Bool {
        shouldSkipControlCharacter(ch)
    }

    func appendNewline(into textStorage: NSTextStorage) {
        textStorage.append(NSAttributedString(string: "\n", attributes: currentTextAttributes))
        currentLineStartLocation = textStorage.length
        cursorColumn = 0
        pendingEraseToEndOfLine = false
    }

    func handleCarriageReturn(in text: String, at index: String.Index, into textStorage: NSTextStorage) -> String.Index {
        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex, text[nextIndex] == "\n" {
            return nextIndex
        }

        // Just move cursor to column 0 - don't erase anything
        cursorColumn = 0
        pendingEraseToEndOfLine = false
        return nextIndex
    }

    func handleBackspace() {
        cursorColumn = max(0, cursorColumn - 1)
        pendingEraseToEndOfLine = false
    }

    func shouldSkipControlCharacter(_ ch: Character) -> Bool {
        let scalarValue = ch.unicodeScalars.first?.value ?? 0
        return scalarValue < 32 && ch != "\t" && ch != "\n"
    }

    func appendTab(into textStorage: NSTextStorage) {
        for _ in 0..<4 {
            putCharacter(" ", into: textStorage)
        }
        pendingEraseToEndOfLine = false
    }

    func currentLineBounds(in textStorage: NSTextStorage) -> (full: NSString, lineEnd: Int) {
        let full = textStorage.string as NSString
        let lineRange = NSRange(
            location: currentLineStartLocation,
            length: max(0, full.length - currentLineStartLocation)
        )
        let newlineRange = full.range(of: "\n", options: [], range: lineRange)
        let lineEnd = (newlineRange.location == NSNotFound) ? full.length : newlineRange.location
        return (full: full, lineEnd: lineEnd)
    }

    func eraseToEndOfLine(in textStorage: NSTextStorage) {
        let bounds = currentLineBounds(in: textStorage)
        let startIndex = max(0, currentLineStartLocation + cursorColumn)
        if startIndex < bounds.lineEnd {
            textStorage.deleteCharacters(
                in: NSRange(location: startIndex, length: bounds.lineEnd - startIndex)
            )
        }
    }

    func eraseInLine(mode: Int, in textStorage: NSTextStorage) {
        let bounds = currentLineBounds(in: textStorage)
        let cursorIndex = max(0, min(currentLineStartLocation + cursorColumn, bounds.lineEnd))

        switch mode {
        case 0:
            eraseToEndOfLine(in: textStorage)
        case 1:
            if currentLineStartLocation < cursorIndex {
                textStorage.deleteCharacters(
                    in: NSRange(
                        location: currentLineStartLocation,
                        length: cursorIndex - currentLineStartLocation
                    )
                )
                currentLineStartLocation = max(0, currentLineStartLocation)
                cursorColumn = 0
            }
        case 2:
            if currentLineStartLocation < bounds.lineEnd {
                textStorage.deleteCharacters(
                    in: NSRange(
                        location: currentLineStartLocation,
                        length: bounds.lineEnd - currentLineStartLocation
                    )
                )
            }
            cursorColumn = 0
        default:
            break
        }
    }

    func deleteCharacters(_ count: Int, in textStorage: NSTextStorage) {
        guard count > 0 else { return }
        let bounds = currentLineBounds(in: textStorage)
        let cursorIndex = max(0, min(currentLineStartLocation + cursorColumn, bounds.lineEnd))
        let deleteEnd = min(bounds.lineEnd, cursorIndex + count)
        if cursorIndex < deleteEnd {
            textStorage.deleteCharacters(in: NSRange(location: cursorIndex, length: deleteEnd - cursorIndex))
        }
    }

    func putCharacter(_ character: String, into textStorage: NSTextStorage) {
        let absoluteCursor = max(0, currentLineStartLocation + cursorColumn)
        let bounds = currentLineBounds(in: textStorage)

        if absoluteCursor < bounds.lineEnd {
            textStorage.replaceCharacters(
                in: NSRange(location: absoluteCursor, length: 1),
                with: NSAttributedString(
                    string: character,
                    attributes: currentTextAttributes
                )
            )
        } else {
            let insertLocation = bounds.lineEnd
            textStorage.insert(
                NSAttributedString(string: character, attributes: currentTextAttributes),
                at: insertLocation
            )
        }

        cursorColumn += 1
    }

    func clearTerminal() {
        guard !isCleaningUp else { return }
        
        // Clear the buffer if available
        if let buffer = screenBuffer {
            buffer.clear()
            screenRenderer?.render(buffer, fontSize: fontSize, fontFamily: fontFamily)
            return
        }
        
        // Fallback to clearing text view directly
        terminalView?.string = ""
    }

    func removeEmbedding() {
        cleanup()
    }

    func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        shellManager.terminate()
        terminalView?.removeFromSuperview()
        terminalView = nil
        screenBuffer = nil
        screenRenderer = nil

        Task { @MainActor [weak self] in
            self?.errorMessage = nil
        }
    }
}
