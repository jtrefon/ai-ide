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
            let attributedChar = NSAttributedString(string: char, attributes: currentAttributes.isEmpty ? nil : currentAttributes)
            result.append(attributedChar)
            currentIndex += 1
        }

        return result
    }
    
    /// Parses ANSI escape sequences and returns rendering attributes
    private func parseANSISequence(_ text: String, from index: Int) -> (attributes: [NSAttributedString.Key: Any], sequenceLength: Int)? {
        let stringIndex = text.index(text.startIndex, offsetBy: index)
        
        guard index + 1 < text.count,
              text[stringIndex] == "\u{001B}",
              text[text.index(after: stringIndex)] == "[" else {
            return nil
        }
        
        var endIndex = index + 2
        var parameters: [Int] = []
        var currentParameter = ""
        
        while endIndex < text.count {
            let charIndex = text.index(text.startIndex, offsetBy: endIndex)
            let char = text[charIndex]
            
            if char.isNumber {
                currentParameter += String(char)
            } else if char == ";" {
                if !currentParameter.isEmpty {
                    parameters.append(Int(currentParameter) ?? 0)
                    currentParameter = ""
                }
            } else if char.isLetter {
                if !currentParameter.isEmpty {
                    parameters.append(Int(currentParameter) ?? 0)
                }
                
                let attributes = processANSIParameters(parameters, command: char)
                let sequenceLength = endIndex - index + 1
                
                return (attributes: attributes, sequenceLength: sequenceLength)
            } else {
                break
            }
            
            endIndex += 1
        }
        
        return nil
    }
    
    /// Processes ANSI parameters and returns text attributes
    private func processANSIParameters(_ parameters: [Int], command: Character) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        guard !parameters.isEmpty else {
            switch command {
            case "m":
                // Reset all attributes
                attributes[.foregroundColor] = defaultForegroundColor
                attributes[.backgroundColor] = defaultBackgroundColor
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            default:
                break
            }
            return attributes
        }
        
        switch command {
        case "m":
            // SGR (Select Graphic Rendition) parameters
            for param in parameters {
                switch param {
                case 0:
                    // Reset
                    attributes[.foregroundColor] = defaultForegroundColor
                    attributes[.backgroundColor] = defaultBackgroundColor
                    attributes[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                case 1:
                    // Bold
                    attributes[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
                case 30...37:
                    // Foreground colors
                    attributes[.foregroundColor] = colorForANSICode(param)
                case 40...47:
                    // Background colors
                    attributes[.backgroundColor] = colorForANSICode(param)
                default:
                    break
                }
            }
        default:
            break
        }
        
        return attributes
    }
    
    /// Maps ANSI color codes to NSColor values
    private func colorForANSICode(_ code: Int) -> NSColor {
        switch code {
        case 30, 40: return NSColor.black
        case 31, 41: return NSColor.red
        case 32, 42: return NSColor.green
        case 33, 43: return NSColor.yellow
        case 34, 44: return NSColor.blue
        case 35, 45: return NSColor.magenta
        case 36, 46: return NSColor.cyan
        case 37, 47: return NSColor.white
        default: return NSColor.green
        }
    }
}
