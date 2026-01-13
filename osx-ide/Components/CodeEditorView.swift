//
//  CodeEditorView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import AppKit

// CodeSelectionContext moved to Services/CodeSelectionContext.swift

extension Notification.Name {
    static let editorHighlightDiagnosticsUpdated = Notification.Name("EditorHighlightDiagnosticsUpdated")
}

struct CodeEditorView: View {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false
    var fontSize: Double = AppConstants.Editor.defaultFontSize
    var fontFamily: String = AppConstants.Editor.defaultFontFamily
    @ObservedObject private var highlightDiagnostics = EditorHighlightDiagnosticsStore.shared
    
    var body: some View {
        GeometryReader { geometry in
            // Text editor (use AppKit's own NSScrollView; avoid nesting in SwiftUI ScrollView)
            TextViewRepresentable(
                text: $text,
                language: language,
                selectedRange: $selectedRange,
                selectionContext: selectionContext,
                showLineNumbers: showLineNumbers,
                wordWrap: wordWrap,
                fontSize: fontSize,
                fontFamily: fontFamily
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(
                Group {
                    if ProcessInfo.processInfo.environment["XCUI_TESTING"] == "1" {
                        Text(highlightDiagnostics.diagnostics)
                            .font(.system(size: 1))
                            .foregroundColor(.clear)
                            .accessibilityIdentifier("EditorHighlightDiagnostics")
                            .accessibilityLabel(highlightDiagnostics.diagnostics)
                            .accessibilityValue(highlightDiagnostics.diagnostics)
                    }
                }
            )
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
    var wordWrap: Bool
    var fontSize: Double
    var fontFamily: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = Self.resolveEditorFont(fontFamily: fontFamily, fontSize: fontSize)
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
        textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, 
                height: CGFloat.greatestFiniteMagnitude
            )
        textView.textContainer?.widthTracksTextView = false
        
        // Set initial text without syntax highlighting to avoid initialization issues
        context.coordinator.isProgrammaticUpdate = true
        textView.string = text
        context.coordinator.isProgrammaticUpdate = false

        // Assign delegate only after initial programmatic setup to avoid publishing SwiftUI state during view updates.
        textView.delegate = context.coordinator
        context.coordinator.attach(textView: textView)
        textView.textStorage?.delegate = context.coordinator.textStorageDelegateProxy
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false

        Task { @MainActor in
            Self.applyWordWrap(wordWrap, to: scrollView, textView: textView)
        }

        if showLineNumbers {
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            scrollView.verticalRulerView = ModernLineNumberRulerView(scrollView: scrollView, textView: textView)

            // Ensure the ruler is laid out and painted on first draw (otherwise it can appear only after scrolling).
            Task { @MainActor in
                scrollView.tile()
                scrollView.verticalRulerView?.needsDisplay = true
            }
        }
        
        // Apply syntax highlighting after the view is set up asynchronously
        context.coordinator.performAsyncHighlight(
            for: text,
            in: textView,
            language: language,
            font: Self.resolveEditorFont(
                fontFamily: fontFamily,
                fontSize: fontSize
            )
        )
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let resolvedFont = Self.resolveEditorFont(fontFamily: fontFamily, fontSize: fontSize)
        let needsRehighlight = syncFont(resolvedFont, for: textView, in: scrollView)
        scheduleWordWrapUpdate(for: scrollView, textView: textView)
        syncTextAndHighlightIfNeeded(
            for: textView,
            coordinator: context.coordinator,
            resolvedFont: resolvedFont,
            needsRehighlight: needsRehighlight
        )
        syncSelectionIfNeeded(for: textView, coordinator: context.coordinator)
        syncRulerVisibilityIfNeeded(for: scrollView, textView: textView)
    }

    private func syncFont(_ resolvedFont: NSFont, for textView: NSTextView, in scrollView: NSScrollView) -> Bool {
        var needsRehighlight = false
        if textView.font != resolvedFont {
            textView.font = resolvedFont
            needsRehighlight = true
        }

        if let ruler = scrollView.verticalRulerView as? ModernLineNumberRulerView {
            ruler.updateFont(resolvedFont)
        }

        return needsRehighlight
    }

    private func scheduleWordWrapUpdate(for scrollView: NSScrollView, textView: NSTextView) {
        Task { @MainActor in
            Self.applyWordWrap(wordWrap, to: scrollView, textView: textView)
        }
    }

    private func syncTextAndHighlightIfNeeded(
        for textView: NSTextView,
        coordinator: Coordinator,
        resolvedFont: NSFont,
        needsRehighlight: Bool
    ) {
        let current = textView.string
        if current != text {
            coordinator.isProgrammaticUpdate = true
            textView.string = text
            coordinator.isProgrammaticUpdate = false

            coordinator.performAsyncHighlight(for: text, in: textView, language: language, font: resolvedFont)
            return
        }

        if needsRehighlight {
            coordinator.performAsyncHighlight(for: current, in: textView, language: language, font: resolvedFont)
        }
    }

    private func syncSelectionIfNeeded(for textView: NSTextView, coordinator: Coordinator) {
        guard let range = selectedRange,
              range.location != NSNotFound,
              range.location + range.length <= (textView.string as NSString).length else {
            return
        }

        coordinator.isProgrammaticSelectionUpdate = true
        defer { coordinator.isProgrammaticSelectionUpdate = false }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    private func syncRulerVisibilityIfNeeded(for scrollView: NSScrollView, textView: NSTextView) {
        let shouldShowRuler = showLineNumbers
        if scrollView.hasVerticalRuler != shouldShowRuler || scrollView.rulersVisible != shouldShowRuler {
            scrollView.hasVerticalRuler = shouldShowRuler
            scrollView.rulersVisible = shouldShowRuler
            if shouldShowRuler && scrollView.verticalRulerView == nil {
                scrollView.verticalRulerView = ModernLineNumberRulerView(scrollView: scrollView, textView: textView)
            }
        }
    }

    static func resolveEditorFont(fontFamily: String, fontSize: Double) -> NSFont {
        let size = CGFloat(fontSize)

        if let font = NSFont(name: fontFamily, size: size) {
            return font
        }

        if let font = NSFontManager.shared.font(
                withFamily: fontFamily, 
                traits: .fixedPitchFontMask, 
                weight: 5, 
                size: size
            ) {
            return font
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func applyWordWrap(_ enabled: Bool, to scrollView: NSScrollView, textView: NSTextView) {
        guard let container = textView.textContainer else { return }

        if enabled {
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: scrollView.contentSize.width, 
                height: CGFloat.greatestFiniteMagnitude
            )
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, 
                height: CGFloat.greatestFiniteMagnitude
            )
            scrollView.hasHorizontalScroller = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

#Preview {
    CodeEditorView(
        text: .constant("func helloWorld() {\n    print(\"Hello, World!\")\n}"),
        language: "swift",
        selectedRange: .constant(nil),
        selectionContext: CodeSelectionContext(),
        showLineNumbers: true,
        wordWrap: false,
        fontSize: AppConstants.Editor.defaultFontSize,
        fontFamily: AppConstants.Editor.defaultFontFamily
    )
    .frame(height: 300)
}
