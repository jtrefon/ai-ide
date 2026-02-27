//
//  ChatInputView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import AppKit

struct ChatInputView: View {
    @Binding var text: String
    let isSending: Bool
    var fontSize: Double
    var fontFamily: String
    let onSend: () -> Void
    
    @FocusState private var isInputFocused: Bool
    @State private var textViewHeight: CGFloat = 44
    private let minimumComposerHeight: CGFloat = 44
    private let maximumComposerHeight: CGFloat = 140

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
    
    /// Computed property to check if send is allowed - ensures reactive updates
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(localized("chat_input.placeholder"))
                            .font(resolveFont(size: fontSize, family: fontFamily))
                            .foregroundColor(Color(NSColor.placeholderTextColor))
                            .padding(.leading, 14)
                            .padding(.top, 12)
                            .padding(.trailing, 44)
                            .allowsHitTesting(false)
                    }

                    MultilineTextField(
                        text: $text,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        minimumHeight: minimumComposerHeight,
                        maximumHeight: maximumComposerHeight,
                        height: $textViewHeight,
                        onSubmit: sendIfPossible
                    )
                    .padding(.leading, 14)
                    .padding(.trailing, 42)
                    .focused($isInputFocused)
                }

                Button(action: sendIfPossible) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(canSend ? Color.accentColor : Color.gray.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(localized("chat_input.send"))
                .accessibilityIdentifier(AccessibilityID.aiChatSendButton)
                .disabled(!canSend)
                .padding(.trailing, 10)
                .padding(.bottom, 9)
            }
            .frame(minHeight: max(minimumComposerHeight, textViewHeight), maxHeight: maximumComposerHeight)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isInputFocused ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: isInputFocused ? 2 : 1
                    )
            )
            .accessibilityIdentifier(AccessibilityID.aiChatInputTextView)
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: textViewHeight)
    }
    
    private func resolveFont(size: Double, family: String) -> Font {
        if let nsFont = NSFont(name: family, size: CGFloat(size)) {
            return Font(nsFont)
        }
        return .system(size: CGFloat(size), weight: .regular, design: .monospaced)
    }

    private func sendIfPossible() {
        guard canSend else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textViewHeight = 44  // Reset height
        onSend()
    }
}

// MARK: - Multiline TextField with Enter to Submit

/// A multiline text field that submits on Enter (without Shift) and allows Shift+Enter for newlines
struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let fontFamily: String
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    @Binding var height: CGFloat
    let onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.setAccessibilityIdentifier(AccessibilityID.aiChatInputTextView)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 11)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: textView.bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // Configure font
        let font: NSFont
        if let nsFont = NSFont(name: fontFamily, size: CGFloat(fontSize)) {
            font = nsFont
        } else {
            font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
        textView.font = font
        textView.textColor = NSColor.labelColor
        
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        // Update text if it changed externally
        if nsView.string != text {
            nsView.string = text
        }
        
        // Update font
        let font: NSFont
        if let nsFont = NSFont(name: fontFamily, size: CGFloat(fontSize)) {
            font = nsFont
        } else {
            font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
        nsView.font = font
        
        // Update height based on content
        DispatchQueue.main.async {
            let textContainer = nsView.textContainer ?? NSTextContainer()
            let usedRect = nsView.layoutManager?.usedRect(for: textContainer)
            let verticalInsets = nsView.textContainerInset.height * 2
            let rawHeight = ceil((usedRect?.height ?? 0) + verticalInsets)
            let newHeight = min(self.maximumHeight, max(self.minimumHeight, rawHeight))
            if abs(self.height - newHeight) > 1 {
                self.height = newHeight
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MultilineTextField
        
        init(_ parent: MultilineTextField) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string

            // Update height based on content
            let textContainer = textView.textContainer ?? NSTextContainer()
            let usedRect = textView.layoutManager?.usedRect(for: textContainer)
            let verticalInsets = textView.textContainerInset.height * 2
            let rawHeight = ceil((usedRect?.height ?? 0) + verticalInsets)
            let newHeight = min(parent.maximumHeight, max(parent.minimumHeight, rawHeight))
            if abs(self.parent.height - newHeight) > 1 {
                self.parent.height = newHeight
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Enter key - submit on Enter, newline on Shift+Enter
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let currentEvent = NSApp.currentEvent
                let isShiftPressed = currentEvent?.modifierFlags.contains(.shift) ?? false
                
                if isShiftPressed {
                    // Allow default behavior - insert newline
                    return false
                } else {
                    // Submit the message
                    parent.onSubmit()
                    return true
                }
            }
            return false
        }
    }
}

struct ChatInputView_Previews: PreviewProvider {
    static var previews: some View {
        ChatInputView(
            text: .constant("Hello, how can you help me?"),
            isSending: false,
            fontSize: 12,
            fontFamily: AppConstants.Editor.defaultFontFamily,
            onSend: {}
        )
    }
}
