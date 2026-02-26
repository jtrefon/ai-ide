//
//  CodeEditorView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import AppKit

// CodeSelectionContext moved to Services/CodeSelectionContext.swift

struct CodeEditorView: View {
    @Binding var text: String
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false
    var fontSize: Double = AppConstantsEditor.defaultFontSize
    var fontFamily: String = AppConstantsEditor.defaultFontFamily
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
                            .accessibilityIdentifier(AccessibilityID.editorHighlightDiagnostics)
                            .accessibilityLabel(highlightDiagnostics.diagnostics)
                            .accessibilityValue(highlightDiagnostics.diagnostics)
                    }
                }
            )
        }
    }
}
