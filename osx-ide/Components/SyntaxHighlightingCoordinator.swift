//
//  SyntaxHighlightingCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import AppKit

/// Manages syntax highlighting for text views with async processing
@MainActor
class SyntaxHighlightingCoordinator {

    // MARK: - Properties

    private var currentHighlightTask: Task<Void, Never>?
    private var pendingHighlightTask: Task<Void, Never>?
    private var lastHighlightResult: NSAttributedString?
    private let syntaxHighlighter = SyntaxHighlighter.shared

    // MARK: - Public Methods

    /// Performs async syntax highlighting with cancellation support
    func performAsyncHighlight(for text: String, in textView: NSTextView, language: String, font: NSFont) {
        currentHighlightTask?.cancel()

        // Store the current selection before update
        let selectedRange = textView.selectedRange
        let typingAttributes = textView.typingAttributes

        // Task inherits @MainActor from caller
        currentHighlightTask = Task {
            // Use incremental highlighting for better performance
            let request = SyntaxHighlighter.HighlightIncrementalRequest(
                code: text,
                language: language,
                font: font,
                previousResult: self.lastHighlightResult
            )
            let attributedString = await syntaxHighlighter.highlightIncremental(request)

            if Task.isCancelled { return }

            // Do NOT replace the entire attributed string (can conflict with AppKit edits on Enter).
            // Instead, apply highlighting in-place by updating attributes only.
            if let textStorage = textView.textStorage {
                let request = ApplyHighlightAttributesRequest(
                    attributedString: attributedString,
                    textStorage: textStorage,
                    selectedRange: selectedRange,
                    typingAttributes: typingAttributes,
                    textView: textView
                )
                await applyHighlightAttributesIncremental(request)
            }

            self.lastHighlightResult = attributedString
        }
    }

    /// Cancels any pending highlight tasks
    func cancelHighlighting() {
        currentHighlightTask?.cancel()
        pendingHighlightTask?.cancel()
    }

    /// Gets the last highlight result
    var lastResult: NSAttributedString? {
        return lastHighlightResult
    }

    // MARK: - Private Methods

    /// Applies highlighting attributes incrementally to avoid conflicts with AppKit edits
    private struct ApplyHighlightAttributesRequest {
        let attributedString: NSAttributedString
        let textStorage: NSTextStorage
        let selectedRange: NSRange
        let typingAttributes: [NSAttributedString.Key: Any]
        let textView: NSTextView
    }

    private func applyHighlightAttributesIncremental(
        _ request: ApplyHighlightAttributesRequest
    ) async {
        // Apply attributes incrementally to avoid conflicts
        let textStorage = request.textStorage
        let fullRange = NSRange(location: 0, length: textStorage.length)

        await MainActor.run {
            textStorage.beginEditing()

            // Apply attributes from the highlighted string
            request.attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                if range.location < textStorage.length {
                    let adjustedRange = NSRange(
                        location: range.location,
                        length: min(range.length, textStorage.length - range.location)
                    )
                    textStorage.addAttributes(attributes, range: adjustedRange)
                }
            }

            textStorage.endEditing()

            // Restore selection and typing attributes
            if request.selectedRange.location <= textStorage.length {
                request.textView.selectedRange = request.selectedRange
            }
            request.textView.typingAttributes = request.typingAttributes
        }
    }
}
