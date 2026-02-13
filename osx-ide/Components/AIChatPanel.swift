import SwiftUI
import Combine
import Foundation

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    let conversationManager: any ConversationManagerProtocol
    @ObservedObject var ui: UIStateManager
    @State private var renderRefreshToken: UInt = 0

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        let _ = renderRefreshToken

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(localized("ai_chat.title"))
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                if let selected = currentSelection, !selected.isEmpty {
                    Text(String(
                        format: localized("ai_chat.context_format"),
                        "\(selected.prefix(30))\(selected.count > 30 ? "..." : "")"
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
                Button(action: {
                    conversationManager.startNewConversation()
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(BorderlessButtonStyle())
                .accessibilityIdentifier("AIChatNewConversationButton")
                .padding(.horizontal)
            }
            .frame(height: 30)
            .background(Color(NSColor.windowBackgroundColor))

            ConversationPlanProgressView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                fontSize: ui.fontSize
            )

            MessageListView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            .clipped()

            // Error display
            if let error = conversationManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            // Input area
            ChatInputView(
                text: inputBinding,
                isSending: conversationManager.isSending,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily,
                onSend: {
                    sendMessage()
                }
            )

            // Mode selector
            HStack(spacing: 8) {
                Image(systemName: conversationManager.currentMode.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(localized("ai_chat.mode"), selection: modeBinding) {
                    ForEach(AIMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Text(conversationManager.currentMode.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
        }
        .accessibilityIdentifier("AIChatPanel")
        .background(Color(NSColor.controlBackgroundColor))
        .onReceive(conversationManager.statePublisher) { _ in
            renderRefreshToken &+= 1
        }
    }

    var currentSelection: String? {
        selectionContext.selectedText.isEmpty ? nil : selectionContext.selectedText
    }

    // MARK: - Bindings

    private var inputBinding: Binding<String> {
        Binding(
            get: { conversationManager.currentInput },
            set: { conversationManager.currentInput = $0 }
        )
    }

    private var modeBinding: Binding<AIMode> {
        Binding(
            get: { conversationManager.currentMode },
            set: { conversationManager.currentMode = $0 }
        )
    }

    private func sendMessage() {
        // Use selected code as context if available
        let context = currentSelection
        let trimmedInput = conversationManager.currentInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        conversationManager.currentInput = trimmedInput
        conversationManager.sendMessage(context: context)
    }

}
