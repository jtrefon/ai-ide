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
    var isSending: Bool
    var fontSize: Double
    var fontFamily: String
    var onSend: () -> Void
    @State private var inputMonitor: Any?
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        HStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(resolveFont(size: fontSize, family: fontFamily))
                    .frame(height: 60)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .accessibilityIdentifier("AIChatInputTextView")
                    .focused($isInputFocused)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .onAppear {
                        // Register for key events
                        self.inputMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            guard isInputFocused else { return event }
                            if event.keyCode == 36 { // Enter key
                                if event.modifierFlags.contains(.shift) {
                                    // Shift+Enter: insert newline (let it through)
                                    return event
                                } else {
                                    // Plain Enter: send message
                                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending {
                                        DispatchQueue.main.async {
                                            onSend()
                                        }
                                    }
                                    return nil // Consume the event
                                }
                            }
                            return event
                        }
                    }
                    .onDisappear {
                        if let monitor = self.inputMonitor {
                            NSEvent.removeMonitor(monitor)
                            self.inputMonitor = nil
                        }
                    }
                
                // Placeholder text
                if text.isEmpty {
                    Text("Type a message... (Shift+Enter for newline)")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            
            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .padding(.leading, 4)
        }
        .padding()
    }
    private func resolveFont(size: Double, family: String) -> Font {
        if let nsFont = NSFont(name: family, size: CGFloat(size)) {
            return Font(nsFont)
        }
        return .system(size: CGFloat(size), weight: .regular, design: .monospaced)
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