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

        var index = text.startIndex
        while index < text.endIndex {
            if let consumed = consumeANSIIfPresent(text, at: index, currentAttributes: &currentAttributes) {
                index = consumed
                continue
            }

            let ch = text[index]
            if ch == "\r" {
                index = text.index(after: index)
                continue
            }

            if shouldSkipPlainTextControlCharacter(ch) {
                index = text.index(after: index)
                continue
            }

            result.append(NSAttributedString(string: String(ch), attributes: currentAttributes))
            index = text.index(after: index)
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

        var index = text.index(after: start)
        guard index < text.endIndex else { return ANSIParseResult(newIndex: index, attributes: [:], shouldSkip: false) }

        if text[index] == "[" {
            index = text.index(after: index)
            return parseCSISequence(text, from: index)
        }

        if text[index] == "]" {
            return parseOSCSequence(text, from: index)
        }

        return ANSIParseResult(newIndex: index, attributes: [:], shouldSkip: false)
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
        var index = start
        while index < text.endIndex {
            if text[index] == "\u{07}" {
                index = text.index(after: index)
                break
            }

            if text[index] == "\u{1B}",
               index < text.index(before: text.endIndex),
               text[text.index(after: index)] == "\\" {
                index = text.index(after: index)
                index = text.index(after: index)
                break
            }

            index = text.index(after: index)
        }

        return ANSIParseResult(newIndex: index, attributes: [:], shouldSkip: true)
    }

    func parseCSISequence(
        _ text: String,
        from start: String.Index
    ) -> ANSIParseResult {
        var index = start
        var parameters: [Int] = []
        var currentParam = ""
        var attributes: [NSAttributedString.Key: Any] = [:]

        while index < text.endIndex {
            let char = text[index]
            if char.isNumber {
                currentParam.append(char)
                index = text.index(after: index)
                continue
            }

            if char == ";" {
                appendCSIParamIfNeeded(&currentParam, into: &parameters)
                index = text.index(after: index)
                continue
            }

            if isCSIFinalByte(char) {
                appendCSIParamIfNeeded(&currentParam, into: &parameters)
                let finalChar = char
                index = text.index(after: index)
                let result = handleCSIFinalCharacter(finalChar, parameters: parameters)
                attributes = result.attributes
                return ANSIParseResult(newIndex: index, attributes: attributes, shouldSkip: result.shouldSkip)
            }

            index = text.index(after: index)
        }

        return ANSIParseResult(newIndex: index, attributes: [:], shouldSkip: false)
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
            "D": { self.handleCursorBackward(parameters) },
            "r": { self.handleSetScrollRegion(parameters) }
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
        guard let terminalView = terminalView else { return ([:], true) }
        guard let storage = terminalView.textStorage else { return ([:], true) }
        eraseInLine(mode: mode, in: storage)
        return ([:], true)
    }

    func handleDeleteCharacters(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let characterCount = max(1, parameters.first ?? 1)
        guard let terminalView = terminalView else { return ([:], true) }
        guard let storage = terminalView.textStorage else { return ([:], true) }
        deleteCharacters(characterCount, in: storage)
        return ([:], true)
    }

    func handleEraseCharacters(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        handleDeleteCharacters(parameters)
    }

    func handleCursorHorizontalAbsolute(
        _ parameters: [Int]
    ) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let col = max(1, parameters.first ?? 1)
        cursorColumn = max(0, col - 1)
        return ([:], true)
    }

    func handleCursorForward(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let columnDelta = max(1, parameters.first ?? 1)
        cursorColumn += columnDelta
        return ([:], true)
    }

    func handleCursorBackward(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        let columnDelta = max(1, parameters.first ?? 1)
        cursorColumn = max(0, cursorColumn - columnDelta)
        return ([:], true)
    }

    func handleSetScrollRegion(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        // For now, just skip - full scroll region support requires virtual screen buffer
        return ([:], true)
    }

    func moveCursorToEndForUnsupportedPositioning() {
        guard let terminalView = terminalView else { return }
        guard let storage = terminalView.textStorage else { return }
        currentLineStartLocation = storage.length
        cursorColumn = 0
        pendingEraseToEndOfLine = false
    }

    func eraseInDisplay(mode: Int) {
        guard let terminalView = terminalView else { return }
        guard let storage = terminalView.textStorage else { return }
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
            case 2:  // Dim
                attributes[.font] = resolveFont(size: fontSize, family: fontFamily, weight: .light)
            case 3:  // Italic
                attributes[.obliqueness] = 0.1
            case 4:  // Underline
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case 7:  // Reverse
                // Swap foreground and background
                let currentFg = currentTextAttributes[.foregroundColor] as? NSColor ?? NSColor.green
                let currentBg = currentTextAttributes[.backgroundColor] as? NSColor ?? NSColor.black
                attributes[.foregroundColor] = currentBg
                attributes[.backgroundColor] = currentFg
            case 22:  // Normal intensity
                attributes[.font] = resolveFont(size: fontSize, family: fontFamily, weight: .regular)
            case 23:  // Not italic
                attributes[.obliqueness] = 0
            case 24:  // Not underlined
                attributes[.underlineStyle] = 0
            case 30...37:
                attributes[.foregroundColor] = ansiColor(param - 30)
            case 38:
                // Extended foreground color - handled separately
                break
            case 39:  // Default foreground
                attributes[.foregroundColor] = NSColor.green
            case 40...47:
                attributes[.backgroundColor] = ansiColor(param - 40)
            case 48:
                // Extended background color - handled separately
                break
            case 49:  // Default background
                attributes[.backgroundColor] = NSColor.black
            case 90...97:  // Bright foreground
                attributes[.foregroundColor] = ansiBrightColor(param - 90)
            case 100...107:  // Bright background
                attributes[.backgroundColor] = ansiBrightColor(param - 100)
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

    func ansiBrightColor(_ code: Int) -> NSColor {
        let brightColors: [NSColor] = [
            NSColor(white: 0.3, alpha: 1.0),   // Bright Black (Dark Gray)
            NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0),  // Bright Red
            NSColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),  // Bright Green
            NSColor(red: 1.0, green: 1.0, blue: 0.3, alpha: 1.0),  // Bright Yellow
            NSColor(red: 0.3, green: 0.3, blue: 1.0, alpha: 1.0),  // Bright Blue
            NSColor(red: 1.0, green: 0.3, blue: 1.0, alpha: 1.0),  // Bright Magenta
            NSColor(red: 0.3, green: 1.0, blue: 1.0, alpha: 1.0),  // Bright Cyan
            NSColor.white  // Bright White
        ]
        return (0..<brightColors.count).contains(code) ? brightColors[code] : NSColor.green
    }
}
