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
    @State private var textViewHeight: CGFloat = 36

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
    
    /// Computed property to check if send is allowed - ensures reactive updates
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if AppRuntimeEnvironment.launchContext.isUITesting {
                TextField(localized("chat_input.placeholder"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(resolveFont(size: fontSize, family: fontFamily))
                    .focused($isInputFocused)
                    .onSubmit(sendIfPossible)
                    .accessibilityLabel(localized("chat_input.placeholder"))
                    .accessibilityIdentifier(AccessibilityID.aiChatInputTextView)
            } else {
                // Text input area with proper styling
                ZStack(alignment: .topLeading) {
                    // Placeholder text
                    if text.isEmpty {
                        Text(localized("chat_input.placeholder"))
                            .font(resolveFont(size: fontSize, family: fontFamily))
                            .foregroundColor(Color(NSColor.placeholderTextColor))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    
                    // Actual text view
                    MultilineTextField(
                        text: $text,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        height: $textViewHeight,
                        onSubmit: sendIfPossible
                    )
                    .focused($isInputFocused)
                }
                .frame(minHeight: min(textViewHeight, 120), maxHeight: 120)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isInputFocused ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isInputFocused ? 2 : 1
                        )
                )
                .accessibilityIdentifier(AccessibilityID.aiChatInputTextView)
            }

            // Send button
            Button(action: sendIfPossible) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(canSend ? Color.accentColor : Color.gray)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(localized("chat_input.send"))
            .accessibilityIdentifier(AccessibilityID.aiChatSendButton)
            .disabled(!canSend)
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        textViewHeight = 36  // Reset height
        onSend()
    }
}

// MARK: - Multiline TextField with Enter to Submit

/// A multiline text field that submits on Enter (without Shift) and allows Shift+Enter for newlines
struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let fontFamily: String
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
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
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
            let usedRect = nsView.layoutManager?.usedRect(for: nsView.textContainer ?? NSTextContainer())
            let newHeight = max(36, (usedRect?.height ?? 0) + 12)  // 12 = textContainerInset * 2
            if abs(self.height - newHeight) > 1 {
                self.height = min(newHeight, 120)
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
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer ?? NSTextContainer())
            let newHeight = max(36, (usedRect?.height ?? 0) + 12)
            if abs(self.parent.height - newHeight) > 1 {
                self.parent.height = min(newHeight, 120)
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
