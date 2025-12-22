//
//  CodeEditorView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

// TODO: Enable selection passing to the AI chat panel for context-aware code actions.

import SwiftUI

// CodeSelectionContext moved to Services/CodeSelectionContext.swift

struct CodeEditorView: View {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    var showLineNumbers: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            // Text editor (use AppKit's own NSScrollView; avoid nesting in SwiftUI ScrollView)
            TextViewRepresentable(
                text: $text,
                language: language,
                selectedRange: $selectedRange,
                selectionContext: selectionContext,
                showLineNumbers: showLineNumbers
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

@MainActor
struct TextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    var showLineNumbers: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // UI Tests need a stable identifier; otherwise `app.textViews.firstMatch` can
        // accidentally match the AI chat input instead of the editor.
        textView.setAccessibilityIdentifier("CodeEditorTextView")
        
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        
        // Set initial text without syntax highlighting to avoid initialization issues
        textView.string = text
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.verticalScroller = LiquidGlassScroller()
        scrollView.horizontalScroller = LiquidGlassScroller()
        scrollView.autohidesScrollers = true

        if showLineNumbers {
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            scrollView.verticalRulerView = ModernLineNumberRulerView(scrollView: scrollView, textView: textView)
        }
        
        // Apply syntax highlighting after the view is set up asynchronously
        context.coordinator.performAsyncHighlight(for: text, in: textView, language: language)
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Avoid unnecessary updates to prevent flicker/blanking
        let current = textView.string
        if current != text {
            context.coordinator.performAsyncHighlight(for: text, in: textView, language: language)
        }
        
        
        // Update selected range if needed
        if let range = selectedRange,
           range.location != NSNotFound,
           range.location + range.length <= (textView.string as NSString).length {
            context.coordinator.isProgrammaticSelectionUpdate = true
            defer { context.coordinator.isProgrammaticSelectionUpdate = false }
            textView.setSelectedRange(range)
        }

        let shouldShowRuler = showLineNumbers
        if scrollView.hasVerticalRuler != shouldShowRuler || scrollView.rulersVisible != shouldShowRuler {
            scrollView.hasVerticalRuler = shouldShowRuler
            scrollView.rulersVisible = shouldShowRuler
            if shouldShowRuler && scrollView.verticalRulerView == nil {
                scrollView.verticalRulerView = ModernLineNumberRulerView(scrollView: scrollView, textView: textView)
            }
        }
        
        // The selection context is now available for the AI chat panel or other consumers.
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TextViewRepresentable
        var isProgrammaticUpdate = false
        var isProgrammaticSelectionUpdate = false
        private var currentHighlightTask: Task<Void, Never>?
        
        init(_ parent: TextViewRepresentable) {
            self.parent = parent
        }

        @MainActor
        func performAsyncHighlight(for text: String, in textView: NSTextView, language: String) {
            currentHighlightTask?.cancel()
            
            let syntaxHighlighter = SyntaxHighlighter.shared
            
            // Task inherits @MainActor from Coordinator
            currentHighlightTask = Task {
                // Since SyntaxHighlighter is @MainActor, we must await its call.
                // Even though it runs on the MainActor, doing it in a Task prevents
                // blocking the current execution flow.
                let attributedString = await syntaxHighlighter.highlight(text, language: language)
                
                if Task.isCancelled { return }
                
                self.isProgrammaticUpdate = true
                textView.textStorage?.beginEditing()
                textView.textStorage?.setAttributedString(attributedString)
                textView.textStorage?.endEditing()
                self.isProgrammaticUpdate = false
            }
        }
        
        @MainActor
        func textDidChange(_ notification: Notification) {
            if isProgrammaticUpdate { return }
            guard let textView = notification.object as? NSTextView else { return }
            
            // Mutate bindings on main actor
            let newText = textView.string
            let newRange = textView.selectedRange
            
            self.parent.text = newText
            self.parent.selectedRange = newRange
            
            // Update the selection context with current selected text and range
            updateSelectionContext(from: textView)
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            if isProgrammaticUpdate || isProgrammaticSelectionUpdate { return }
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.selectedRange = textView.selectedRange
            updateSelectionContext(from: textView)
        }

        @MainActor
        private func updateSelectionContext(from textView: NSTextView) {
            let range = textView.selectedRange
            if range.location != NSNotFound,
               range.length > 0,
               range.location + range.length <= (textView.string as NSString).length {
                let selected = (textView.string as NSString).substring(with: range)
                parent.selectionContext.selectedText = selected
                parent.selectionContext.selectedRange = range
            } else {
                parent.selectionContext.selectedText = ""
                parent.selectionContext.selectedRange = nil
            }
        }
    }
}

#Preview {
    CodeEditorView(
        text: .constant("func helloWorld() {\n    print(\"Hello, World!\")\n}"),
        language: "swift",
        selectedRange: .constant(nil),
        selectionContext: CodeSelectionContext(),
        showLineNumbers: true
    )
    .frame(height: 300)
}
