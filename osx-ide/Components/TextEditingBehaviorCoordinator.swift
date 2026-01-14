//
//  TextEditingBehaviorCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import AppKit

/// Manages text editing behaviors like auto-bracketing and auto-indentation
@MainActor
class TextEditingBehaviorCoordinator {

    // MARK: - Properties

    private var isProgrammaticUpdate = false

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Sets programmatic update flag
    func setProgrammaticUpdate(_ isProgrammatic: Bool) {
        self.isProgrammaticUpdate = isProgrammatic
    }

    /// Handles text changes in the text view
    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn _: NSRange,
        replacementString: String?
    ) -> Bool {
        if isProgrammaticUpdate { return true }
        guard let replacementString else { return true }

        // Only apply behaviors for simple insertions (typing). Let multi-char replacements go through.
        if replacementString.count != 1 { return true }

        let ch = replacementString

        // Auto-bracketing
        if let (open, close) = bracketPair(for: ch) {
            handleBracketInsertion(textView: textView, open: open, close: close)
            return false
        }

        // Auto-indentation
        if ch == "\n" {
            handleNewlineInsertion(textView: textView)
            return false
        }

        return true
    }

    /// Handles did process editing events
    func handleDidProcessEditing(text: String) {
        _ = text
    }

    // MARK: - Private Methods

    /// Returns the bracket pair for a character
    private func bracketPair(for character: String) -> (String, String)? {
        switch character {
        case "(": return ("(", ")")
        case "[": return ("[", "]")
        case "{": return ("{", "}")
        case "\"": return ("\"", "\"")
        case "'": return ("'", "'")
        default: return nil
        }
    }

    /// Handles bracket insertion with auto-closing
    private func handleBracketInsertion(textView: NSTextView, open: String, close: String) {
        let selectedRange = textView.selectedRange

        // Insert opening bracket
        textView.insertText(open, replacementRange: selectedRange)

        // Insert closing bracket
        textView.insertText(close, replacementRange: textView.selectedRange)

        // Position cursor between brackets
        if let newRange = textView.selectedRange.location > 0 ?
            NSRange(location: textView.selectedRange.location - 1, length: 0) : nil {
            textView.selectedRange = newRange
        }
    }

    /// Handles newline insertion with auto-indentation
    private func handleNewlineInsertion(textView: NSTextView) {
        let currentLine = getCurrentLine(from: textView)
        let leadingWhitespace = extractLeadingWhitespace(from: currentLine)
        let increasedIndentation = calculateIncreasedIndentation(for: currentLine)

        let newIndentation = leadingWhitespace + increasedIndentation

        // Insert newline with proper indentation
        textView.insertText("\n" + newIndentation, replacementRange: textView.selectedRange)
    }

    /// Gets the current line from the text view
    private func getCurrentLine(from textView: NSTextView) -> String {
        let text = textView.string
        let selectedRange = textView.selectedRange
        let ns = text as NSString

        // Find the start of the current line
        var lineStart = selectedRange.location
        while lineStart > 0 {
            if ns.character(at: lineStart - 1) == 10 {
                break
            }
            lineStart -= 1
        }

        // Find the end of the current line
        var lineEnd = selectedRange.location
        while lineEnd < ns.length {
            if ns.character(at: lineEnd) == 10 {
                break
            }
            lineEnd += 1
        }

        return ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
    }

    /// Extracts leading whitespace from a line
    private func extractLeadingWhitespace(from line: String) -> String {
        var result = ""
        for ch in line {
            if ch == " " || ch == "\t" {
                result.append(ch)
            } else {
                break
            }
        }
        return result
    }

    /// Calculates increased indentation based on current line
    private func calculateIncreasedIndentation(for line: String) -> String {
        let openCounts = calculateOpenDelimiters(in: line)
        return String(repeating: "    ", count: openCounts)
    }

    private func calculateOpenDelimiters(in line: String) -> Int {
        var openBrackets = 0
        var openBraces = 0
        var openParens = 0

        for ch in line {
            applyDelimiterDelta(for: ch, openBraces: &openBraces, openBrackets: &openBrackets, openParens: &openParens)
        }

        return openBraces + openBrackets + openParens
    }

    private func applyDelimiterDelta(
        for character: Character,
        openBraces: inout Int,
        openBrackets: inout Int,
        openParens: inout Int
    ) {
        switch character {
        case "{":
            openBraces += 1
        case "}":
            openBraces = max(0, openBraces - 1)
        case "[":
            openBrackets += 1
        case "]":
            openBrackets = max(0, openBrackets - 1)
        case "(":
            openParens += 1
        case ")":
            openParens = max(0, openParens - 1)
        default:
            break
        }
    }
}
