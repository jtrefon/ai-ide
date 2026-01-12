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
            let attributedString = await syntaxHighlighter.highlightIncremental(
                code: text,
                language: language,
                font: font,
                previousResult: self.lastHighlightResult
            )
            
            if Task.isCancelled { return }
            
            // Do NOT replace the entire attributed string (can conflict with AppKit edits on Enter).
            // Instead, apply highlighting in-place by updating attributes only.
            if let textStorage = textView.textStorage {
                await applyHighlightAttributesIncremental(
                    attributedString: attributedString,
                    to: textStorage,
                    selectedRange: selectedRange,
                    typingAttributes: typingAttributes,
                    textView: textView
                )
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
    private func applyHighlightAttributesIncremental(
        attributedString: NSAttributedString,
        to textStorage: NSTextStorage,
        selectedRange: NSRange,
        typingAttributes: [NSAttributedString.Key: Any],
        textView: NSTextView
    ) async {
        // Apply attributes incrementally to avoid conflicts
        let fullRange = NSRange(location: 0, length: textStorage.length)
        
        await MainActor.run {
            textStorage.beginEditing()
            
            // Apply attributes from the highlighted string
            attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
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
            if selectedRange.location <= textStorage.length {
                textView.selectedRange = selectedRange
            }
            textView.typingAttributes = typingAttributes
        }
    }
}
