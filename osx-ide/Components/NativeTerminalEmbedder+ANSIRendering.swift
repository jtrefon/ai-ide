import AppKit
import Foundation

extension NativeTerminalEmbedder {

    struct ANSIParseResult {
        let newIndex: String.Index
        let attributes: [NSAttributedString.Key: Any]
        let shouldSkip: Bool
    }
    /// Process ANSI escape sequences and return attributed string
    func processANSIEscapeSequences(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        var currentAttributes: [NSAttributedString.Key: Any] = [
            .font: resolveFont(size: fontSize, family: fontFamily),
            .foregroundColor: NSColor.green,
            .paragraphStyle: paragraphStyle
        ]

        var i = text.startIndex
        while i < text.endIndex {
            if let consumed = consumeANSIIfPresent(text, at: i, currentAttributes: &currentAttributes) {
                i = consumed
                continue
            }

            let ch = text[i]
            if ch == "\r" {
                i = text.index(after: i)
                continue
            }

            if shouldSkipPlainTextControlCharacter(ch) {
                i = text.index(after: i)
                continue
            }

            result.append(NSAttributedString(string: String(ch), attributes: currentAttributes))
            i = text.index(after: i)
        }

        return result
    }

    private func consumeANSIIfPresent(
        _ text: String,
        at index: String.Index,
        currentAttributes: inout [NSAttributedString.Key: Any]
    ) -> String.Index? {
        guard text[index] == "\u{1B}" else { return nil }
        guard let result = parseANSISequence(text, from: index) else { return nil }
        if !result.shouldSkip {
            currentAttributes.merge(result.attributes) { (_, new) in new }
        }
        return result.newIndex
    }

    private func shouldSkipPlainTextControlCharacter(_ ch: Character) -> Bool {
        let scalarValue = ch.unicodeScalars.first?.value ?? 0
        return scalarValue < 32 && ch != "\n" && ch != "\t"
    }

    func parseANSISequence(
        _ text: String,
        from start: String.Index
    ) -> ANSIParseResult? {
        guard start < text.endIndex, text[start] == "\u{1B}" else { return nil }

        var i = text.index(after: start)
        guard i < text.endIndex else { return ANSIParseResult(newIndex: i, attributes: [:], shouldSkip: false) }

        if text[i] == "[" {
            i = text.index(after: i)
            return parseCSISequence(text, from: i)
        }

        if text[i] == "]" {
            return parseOSCSequence(text, from: i)
        }

        return ANSIParseResult(newIndex: i, attributes: [:], shouldSkip: false)
    }

    private func appendCSIParamIfNeeded(_ currentParam: inout String, into parameters: inout [Int]) {
        guard !currentParam.isEmpty else { return }
        parameters.append(Int(currentParam) ?? 0)
        currentParam = ""
    }

    private func isCSIFinalByte(_ char: Character) -> Bool {
        (char >= "A" && char <= "Z") || (char >= "a" && char <= "z")
    }

    func parseOSCSequence(
        _ text: String,
        from start: String.Index
    ) -> ANSIParseResult {
        var i = start
        while i < text.endIndex {
            if text[i] == "\u{07}" {
                i = text.index(after: i)
                break
            }

            if text[i] == "\u{1B}", i < text.index(before: text.endIndex), text[text.index(after: i)] == "\\" {
                i = text.index(after: i)
                i = text.index(after: i)
                break
            }

            i = text.index(after: i)
        }

        return ANSIParseResult(newIndex: i, attributes: [:], shouldSkip: true)
    }

    func parseCSISequence(
        _ text: String,
        from start: String.Index
    ) -> ANSIParseResult {
        var i = start
        var parameters: [Int] = []
        var currentParam = ""
        var attributes: [NSAttributedString.Key: Any] = [:]

        while i < text.endIndex {
            let char = text[i]
            if char.isNumber {
                currentParam.append(char)
                i = text.index(after: i)
                continue
            }

            if char == ";" {
                appendCSIParamIfNeeded(&currentParam, into: &parameters)
                i = text.index(after: i)
                continue
            }

            if isCSIFinalByte(char) {
                appendCSIParamIfNeeded(&currentParam, into: &parameters)
                let finalChar = char
                i = text.index(after: i)
                let result = handleCSIFinalCharacter(finalChar, parameters: parameters)
                attributes = result.attributes
                return ANSIParseResult(newIndex: i, attributes: attributes, shouldSkip: result.shouldSkip)
            }

            i = text.index(after: i)
        }

        return ANSIParseResult(newIndex: i, attributes: [:], shouldSkip: false)
    }

    func handleCSIFinalCharacter(
        _ finalChar: Character,
        parameters: [Int]
    ) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let handlers: [Character: () -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool)] = [
            "m": { self.handleSGR(parameters) },
            "H": { self.handleCursorPositioning() },
            "f": { self.handleCursorPositioning() },
            "J": { self.handleEraseInDisplay(parameters) },
            "K": { self.handleEraseInLine(parameters) },
            "P": { self.handleDeleteCharacters(parameters) },
            "X": { self.handleEraseCharacters(parameters) },
            "A": { self.handleCursorPositioning() },
            "B": { self.handleCursorPositioning() },
            "G": { self.handleCursorHorizontalAbsolute(parameters) },
            "C": { self.handleCursorForward(parameters) },
            "D": { self.handleCursorBackward(parameters) }
        ]

        return handlers[finalChar]?() ?? ([:], true)
    }

    func handleSGR(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        (applySGRParameters(parameters), false)
    }

    func handleCursorPositioning() -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        moveCursorToEndForUnsupportedPositioning()
        return ([:], true)
    }

    func handleEraseInDisplay(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let mode = parameters.first ?? 0
        eraseInDisplay(mode: mode)
        return ([:], true)
    }

    func handleEraseInLine(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let mode = parameters.first ?? 0
        if let terminalView = terminalView, let storage = terminalView.textStorage {
            eraseInLine(mode: mode, in: storage)
        }
        return ([:], true)
    }

    func handleDeleteCharacters(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let n = max(1, parameters.first ?? 1)
        if let terminalView = terminalView, let storage = terminalView.textStorage {
            deleteCharacters(n, in: storage)
        }
        return ([:], true)
    }

    func handleEraseCharacters(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        handleDeleteCharacters(parameters)
    }

    func handleCursorHorizontalAbsolute(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let col = max(1, parameters.first ?? 1)
        cursorColumn = max(0, col - 1)
        return ([:], true)
    }

    func handleCursorForward(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let n = max(1, parameters.first ?? 1)
        cursorColumn += n
        return ([:], true)
    }

    func handleCursorBackward(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let n = max(1, parameters.first ?? 1)
        cursorColumn = max(0, cursorColumn - n)
        return ([:], true)
    }

    func moveCursorToEndForUnsupportedPositioning() {
        if let terminalView = terminalView, let storage = terminalView.textStorage {
            currentLineStartLocation = storage.length
            cursorColumn = 0
            pendingEraseToEndOfLine = false
        }
    }

    func eraseInDisplay(mode: Int) {
        if let terminalView = terminalView, let storage = terminalView.textStorage {
            if mode == 2 || mode == 3 {
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
                currentLineStartLocation = 0
                cursorColumn = 0
                pendingEraseToEndOfLine = false
            } else {
                currentLineStartLocation = storage.length
                cursorColumn = 0
                pendingEraseToEndOfLine = false
            }
        }
    }

    func applySGRParameters(_ parameters: [Int]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        for param in parameters.isEmpty ? [0] : parameters {
            switch param {
            case 0:
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                attributes = [
                    .font: resolveFont(size: fontSize, family: fontFamily),
                    .foregroundColor: NSColor.green,
                    .paragraphStyle: paragraphStyle
                ]
            case 1:
                attributes[.font] = resolveFont(size: fontSize, family: fontFamily, weight: .bold)
            case 30...37:
                attributes[.foregroundColor] = ansiColor(param - 30)
            case 40...47:
                attributes[.backgroundColor] = ansiColor(param - 40)
            default:
                break
            }
        }
        return attributes
    }

    func ansiColor(_ code: Int) -> NSColor {
        let colors: [NSColor] = [
            .black,
            .red,
            .green,
            .yellow,
            .blue,
            .magenta,
            .cyan,
            .white
        ]
        return (0..<colors.count).contains(code) ? colors[code] : .green
    }
}
