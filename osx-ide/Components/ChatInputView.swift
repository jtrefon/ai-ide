//
//  ChatInputView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isSending: Bool
    var fontSize: Double
    var fontFamily: String
    let onSend: () -> Void

    @FocusState private var isInputFocused: Bool

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func resolveFont(size: Double, family: String) -> Font {
        if let nsFont = NSFont(name: family, size: CGFloat(size)) {
            return Font(nsFont)
        }
        return .system(size: CGFloat(size), weight: .regular, design: .monospaced)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(localized("chat_input.placeholder"), text: $text, axis: .vertical)
                .font(resolveFont(size: fontSize, family: fontFamily))
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .lineLimit(1...6)
                .fixedSize(horizontal: false, vertical: true)
                .onSubmit(sendIfPossible)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isInputFocused ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.3),
                            lineWidth: isInputFocused ? 1.5 : 0.5
                        )
                )
                .accessibilityIdentifier(AccessibilityID.aiChatInputTextView)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: sendIfPossible) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            canSend ? Color.white : Color(NSColor.placeholderTextColor).opacity(0.5),
                            canSend ? Color.accentColor : Color.clear
                        )
                        .background {
                            if canSend {
                                Circle()
                                    .fill(Color.accentColor)
                                    .glassEffect(.regular, in: Circle())
                            }
                        }
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("chat_input.send"))
                .accessibilityIdentifier(AccessibilityID.aiChatSendButton)
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func sendIfPossible() {
        guard canSend else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend()
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
