import AppKit
import Foundation

extension NativeTerminalEmbedder {
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
            if text[i] == "\u{1B}" {
                if let (newIndex, newAttributes, shouldSkip) = parseANSISequence(text, from: i) {
                    if !shouldSkip {
                        currentAttributes.merge(newAttributes) { (_, new) in new }
                    }
                    i = newIndex
                    continue
                }
            }

            if text[i] == "\r" {
                i = text.index(after: i)
                continue
            }

            let char = String(text[i])
            let scalarValue = char.unicodeScalars.first?.value ?? 0
            if scalarValue < 32 && char != "\n" && char != "\t" {
                i = text.index(after: i)
                continue
            }

            result.append(NSAttributedString(string: char, attributes: currentAttributes))
            i = text.index(after: i)
        }

        return result
    }

    func parseANSISequence(
        _ text: String,
        from start: String.Index
    ) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool)? {
        guard start < text.endIndex, text[start] == "\u{1B}" else { return nil }

        var i = text.index(after: start)
        guard i < text.endIndex else { return (i, [:], false) }

        if text[i] == "[" {
            i = text.index(after: i)
            return parseCSISequence(text, from: i)
        }

        if text[i] == "]" {
            return parseOSCSequence(text, from: i)
        }

        return (i, [:], false)
    }

    func parseOSCSequence(
        _ text: String,
        from start: String.Index
    ) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
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

        return (i, [:], true)
    }

    func parseCSISequence(
        _ text: String,
        from start: String.Index
    ) -> (newIndex: String.Index, attributes: [NSAttributedString.Key: Any], shouldSkip: Bool) {
        var i = start
        var parameters: [Int] = []
        var currentParam = ""
        var attributes: [NSAttributedString.Key: Any] = [:]

        while i < text.endIndex {
            let char = text[i]
            if char.isNumber {
                currentParam.append(char)
            } else if char == ";" {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                    currentParam = ""
                }
            } else if (char >= "A" && char <= "Z") || (char >= "a" && char <= "z") {
                if !currentParam.isEmpty {
                    parameters.append(Int(currentParam) ?? 0)
                }

                let finalChar = char
                i = text.index(after: i)
                let result = handleCSIFinalCharacter(finalChar, parameters: parameters)
                if let returnedAttributes = result.attributes {
                    attributes = returnedAttributes
                }
                return (i, attributes, result.shouldSkip)
            }
            i = text.index(after: i)
        }

        return (i, [:], false)
    }

    func handleCSIFinalCharacter(
        _ finalChar: Character,
        parameters: [Int]
    ) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let handlers: [Character: () -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool)] = [
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

        return handlers[finalChar]?() ?? (nil, true)
    }

    func handleSGR(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        (applySGRParameters(parameters), false)
    }

    func handleCursorPositioning() -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        moveCursorToEndForUnsupportedPositioning()
        return (nil, true)
    }

    func handleEraseInDisplay(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let mode = parameters.first ?? 0
        eraseInDisplay(mode: mode)
        return (nil, true)
    }

    func handleEraseInLine(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let mode = parameters.first ?? 0
        if let terminalView = terminalView, let storage = terminalView.textStorage {
            eraseInLine(mode: mode, in: storage)
        }
        return (nil, true)
    }

    func handleDeleteCharacters(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let n = max(1, parameters.first ?? 1)
        if let terminalView = terminalView, let storage = terminalView.textStorage {
            deleteCharacters(n, in: storage)
        }
        return (nil, true)
    }

    func handleEraseCharacters(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        handleDeleteCharacters(parameters)
    }

    func handleCursorHorizontalAbsolute(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let col = max(1, parameters.first ?? 1)
        cursorColumn = max(0, col - 1)
        return (nil, true)
    }

    func handleCursorForward(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let n = max(1, parameters.first ?? 1)
        cursorColumn += n
        return (nil, true)
    }

    func handleCursorBackward(_ parameters: [Int]) -> (attributes: [NSAttributedString.Key: Any]?, shouldSkip: Bool) {
        let n = max(1, parameters.first ?? 1)
        cursorColumn = max(0, cursorColumn - n)
        return (nil, true)
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
