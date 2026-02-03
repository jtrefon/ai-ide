import AppKit
import Foundation

extension NativeTerminalEmbedder {
    func appendOutput(_ text: String) {
        guard !isCleaningUp, terminalView != nil else { return }

        eventBus.publish(TerminalOutputProducedEvent(output: text))

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let terminalView = self.terminalView else { return }
            guard !self.isCleaningUp else { return }
            let shouldAutoscroll = self.isNearBottom(terminalView)
            self.applyTerminalOutput(text, to: terminalView)

            if shouldAutoscroll {
                let range = NSRange(location: terminalView.string.count, length: 0)
                terminalView.setSelectedRange(range)
                terminalView.scrollRangeToVisible(range)
            }
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
            return handleCarriageReturn(in: text, at: index)
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

    func handleCarriageReturn(in text: String, at index: String.Index) -> String.Index {
        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex, text[nextIndex] == "\n" {
            return nextIndex
        }

        cursorColumn = 0
        pendingEraseToEndOfLine = true
        return nextIndex
    }

    func handleBackspace() {
        cursorColumn = max(0, cursorColumn - 1)
        pendingEraseToEndOfLine = false
    }

    func shouldSkipControlCharacter(_ ch: Character) -> Bool {
        let scalarValue = ch.unicodeScalars.first?.value ?? 0
        return scalarValue < 32 && ch != "\t"
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

        Task { @MainActor [weak self] in
            self?.errorMessage = nil
        }
    }
}
