//
//  CodeEditorView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

// TODO: Enable selection passing to the AI chat panel for context-aware code actions.

import SwiftUI

class CodeSelectionContext: ObservableObject {
    @Published var selectedText: String = ""
    @Published var selectedRange: NSRange? = nil
}

struct CodeEditorView: View {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    
    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                // Line numbers
                LineNumbersView(text: text)
                    .frame(width: 45)
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                
                // Text editor (use AppKit's own NSScrollView; avoid nesting in SwiftUI ScrollView)
                TextViewRepresentable(
                    text: $text,
                    language: language,
                    selectedRange: $selectedRange,
                    selectionContext: selectionContext
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct LineNumbersView: View {
    let text: String
    
    var body: some View {
        let lines = text.components(separatedBy: .newlines).count
        let lineCount = max(1, lines)
        
        // Use a ScrollView with LazyVStack to prevent rendering all line numbers at once
        // This stops the UI from "exploding" with large files.
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<lineCount, id: \.self) { lineIndex in
                    Text("\(lineIndex + 1)")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 15, alignment: .trailing)
                        .padding(.trailing, 4)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct TextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    
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
        scrollView.autohidesScrollers = true
        
        // Apply syntax highlighting after the view is set up
        DispatchQueue.main.async {
            let attributedString = SyntaxHighlighter.shared.highlight(text, language: language)
            textView.textStorage?.setAttributedString(attributedString)
            // Ensure text color is set so content is visible
            textView.textColor = NSColor.labelColor
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Avoid unnecessary updates to prevent flicker/blanking
        let current = textView.string
        if current != text {
            context.coordinator.isProgrammaticUpdate = true
            defer { context.coordinator.isProgrammaticUpdate = false }
            let attributedString = SyntaxHighlighter.shared.highlight(text, language: language)
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(attributedString)
            textView.textStorage?.endEditing()
        }
        
        
        // Update selected range if needed
        if let range = selectedRange,
           range.location != NSNotFound,
           range.location + range.length <= (textView.string as NSString).length {
            textView.setSelectedRange(range)
        }
        
        // The selection context is now available for the AI chat panel or other consumers.
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TextViewRepresentable
        var isProgrammaticUpdate = false
        
        init(_ parent: TextViewRepresentable) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if isProgrammaticUpdate { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            // Update selected range
            parent.selectedRange = textView.selectedRange
            
            // Update the selection context with current selected text and range
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
        selectionContext: CodeSelectionContext()
    )
    .frame(height: 300)
}

