//
//  TerminalANSIRenderer.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation
import AppKit

/// Handles ANSI escape sequence processing and rendering for terminal output
@MainActor
class TerminalANSIRenderer {
    
    // MARK: - Color Configuration
    
    private var defaultForegroundColor: NSColor = .green
    private var defaultBackgroundColor: NSColor = .black
    
    // MARK: - Initialization
    
    init(foregroundColor: NSColor = .green, backgroundColor: NSColor = .black) {
        self.defaultForegroundColor = foregroundColor
        self.defaultBackgroundColor = backgroundColor
    }
    
    // MARK: - Color Configuration
    
    func updateColors(foreground: NSColor, background: NSColor) {
        self.defaultForegroundColor = foreground
        self.defaultBackgroundColor = background
    }
    
    // MARK: - ANSI Processing
    
    /// Processes ANSI escape sequences in terminal text
    func processANSIEscapeSequences(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var currentIndex = 0
        var currentAttributes: [NSAttributedString.Key: Any] = [:]

        while currentIndex < text.count {
            let stringIndex = text.index(text.startIndex, offsetBy: currentIndex)

            if text[stringIndex] == "\u{001B}" {
                if let parsed = parseANSISequence(text, from: currentIndex) {
                    if !parsed.attributes.isEmpty {
                        currentAttributes = parsed.attributes
                    }
                    currentIndex += parsed.sequenceLength
                    continue
                }
            }

            let char = String(text[stringIndex])
            let attributedChar = NSAttributedString(
                string: char, 
                attributes: currentAttributes.isEmpty ? nil : currentAttributes
            )
            result.append(attributedChar)
            currentIndex += 1
        }

        return result
    }
    
    /// Parses ANSI escape sequences and returns rendering attributes
    private func parseANSISequence(
            _ text: String, 
            from index: Int
        ) -> (attributes: [NSAttributedString.Key: Any], sequenceLength: Int)? {
        guard isValidANSIPrefix(text, at: index) else {
            return nil
        }

        guard let parsed = parseANSIParametersAndCommand(text, startIndex: index + 2) else {
            return nil
        }

        let attributes = processANSIParameters(parsed.parameters, command: parsed.command)
        let sequenceLength = parsed.endIndex - index + 1
        return (attributes: attributes, sequenceLength: sequenceLength)
    }
    
    /// Processes ANSI parameters and returns text attributes
    private func processANSIParameters(_ parameters: [Int], command: Character) -> [NSAttributedString.Key: Any] {
        guard command == "m" else {
            return [:]
        }

        if parameters.isEmpty {
            return resetTextAttributes()
        }

        return applySGRParameters(parameters)
    }
    
    /// Maps ANSI color codes to NSColor values
    private func colorForANSICode(_ code: Int) -> NSColor {
        let baseColors: [NSColor] = [
            .black,
            .red,
            .green,
            .yellow,
            .blue,
            .magenta,
            .cyan,
            .white
        ]

        if (30...37).contains(code) {
            return baseColors[code - 30]
        }

        if (40...47).contains(code) {
            return baseColors[code - 40]
        }

        return .green
    }

    private func isValidANSIPrefix(_ text: String, at index: Int) -> Bool {
        let stringIndex = text.index(text.startIndex, offsetBy: index)

        guard index + 1 < text.count else {
            return false
        }

        return text[stringIndex] == "\u{001B}" && text[text.index(after: stringIndex)] == "["
    }

    private func parseANSIParametersAndCommand(
        _ text: String,
        startIndex: Int
    ) -> (parameters: [Int], command: Character, endIndex: Int)? {
        var endIndex = startIndex
        var parameters: [Int] = []
        var currentParameter = ""

        while endIndex < text.count {
            let charIndex = text.index(text.startIndex, offsetBy: endIndex)
            let char = text[charIndex]

            if char.isNumber {
                currentParameter += String(char)
            } else if char == ";" {
                appendCurrentParameterIfNeeded(&currentParameter, to: &parameters)
            } else if char.isLetter {
                appendCurrentParameterIfNeeded(&currentParameter, to: &parameters)
                return (parameters: parameters, command: char, endIndex: endIndex)
            } else {
                return nil
            }

            endIndex += 1
        }

        return nil
    }

    private func appendCurrentParameterIfNeeded(
        _ currentParameter: inout String,
        to parameters: inout [Int]
    ) {
        guard !currentParameter.isEmpty else {
            return
        }

        parameters.append(Int(currentParameter) ?? 0)
        currentParameter = ""
    }

    private func resetTextAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: defaultForegroundColor,
            .backgroundColor: defaultBackgroundColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
    }

    private func applySGRParameters(_ parameters: [Int]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]

        for param in parameters {
            if param == 0 {
                attributes.merge(resetTextAttributes(), uniquingKeysWith: { _, new in new })
                continue
            }

            if param == 1 {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
                continue
            }

            if (30...37).contains(param) {
                attributes[.foregroundColor] = colorForANSICode(param)
                continue
            }

            if (40...47).contains(param) {
                attributes[.backgroundColor] = colorForANSICode(param)
                continue
            }
        }

        return attributes
    }
}
