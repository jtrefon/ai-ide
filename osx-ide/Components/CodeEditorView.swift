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
    let paneID: FileEditorStateManager.PaneID
    @Binding var text: String
    let filePath: String?
    var language: String
    @Binding var selectedRange: NSRange?
    @ObservedObject var selectionContext: CodeSelectionContext
    let inlineCompletionEngine: InlineCompletionEngine
    var inlineCompletionDebugOverlayEnabled: Bool = false
    var showLineNumbers: Bool = true
    var wordWrap: Bool = false
    var fontSize: Double = AppConstantsEditor.defaultFontSize
    var fontFamily: String = AppConstantsEditor.defaultFontFamily
    @ObservedObject private var highlightDiagnostics = EditorHighlightDiagnosticsStore.shared
    @ObservedObject private var inlineCompletionDebugStore = InlineCompletionDebugStore.shared

    var body: some View {
        GeometryReader { geometry in
            // Text editor (use AppKit's own NSScrollView; avoid nesting in SwiftUI ScrollView)
            TextViewRepresentable(
                paneID: paneID,
                text: $text,
                filePath: filePath,
                language: language,
                selectedRange: $selectedRange,
                selectionContext: selectionContext,
                inlineCompletionEngine: inlineCompletionEngine,
                showLineNumbers: showLineNumbers,
                wordWrap: wordWrap,
                fontSize: fontSize,
                fontFamily: fontFamily
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(
                diagnosticsOverlay,
                alignment: .topLeading
            )
            .overlay(
                inlineCompletionDebugOverlay,
                alignment: .topTrailing
            )
        }
    }

    @ViewBuilder
    private var diagnosticsOverlay: some View {
        if ProcessInfo.processInfo.environment["XCUI_TESTING"] == "1" {
            let diagnosticsText = highlightDiagnostics.diagnostics.isEmpty ? "pending" : highlightDiagnostics.diagnostics
            Text(diagnosticsText)
                .font(.system(size: 8))
                .foregroundColor(.primary)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(false)
                .accessibilityIdentifier(AccessibilityID.editorHighlightDiagnostics)
                .accessibilityLabel(diagnosticsText)
                .accessibilityValue(diagnosticsText)
        }
    }

    @ViewBuilder
    private var inlineCompletionDebugOverlay: some View {
        if inlineCompletionDebugOverlayEnabled {
            let state = inlineCompletionDebugStore.state(for: paneID)

            VStack(alignment: .leading, spacing: 4) {
                Text("Inline Completion")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))

                if let state {
                    Text("\(state.source.rawValue) • \(Int(state.latencyMs))ms • \(Int(state.confidenceScore * 100))%")
                    Text(state.isMultiline ? "multiline" : "single-line")
                    Text(state.suggestionPreview.isEmpty ? "no preview" : state.suggestionPreview)
                        .lineLimit(3)
                } else {
                    Text("idle")
                    Text(filePath ?? "no file")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
            )
            .padding(12)
            .allowsHitTesting(false)
        }
    }
}
