import SwiftUI

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    @ObservedObject var conversationManager: ConversationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                if let selected = currentSelection, !selected.isEmpty {
                    Text("Context: \"\(selected.prefix(30))\(selected.count > 30 ? "..." : "")\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                Button(action: {
                    conversationManager.clearConversation()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.horizontal)
            }
            .frame(height: 30)
            .nativeGlassBackground(.header)
            
            // Messages list
            MessageListView(messages: conversationManager.messages)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
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
                text: $conversationManager.currentInput,
                isSending: conversationManager.isSending,
                onSend: {
                    sendMessage()
                }
            )
        }
        .accessibilityIdentifier("AIChatPanel")
        .background(Color(NSColor.controlBackgroundColor))
    }

    var currentSelection: String? { 
        selectionContext.selectedText.isEmpty ? nil : selectionContext.selectedText
    }

    private func sendMessage() {
        // Use selected code as context if available
        let context = currentSelection
        conversationManager.currentInput = conversationManager.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationManager.sendMessage(context: context)
    }
}

#Preview {
    let ctx = CodeSelectionContext()
    ctx.selectedText = "func helloWorld() { print(\"Hello\") }"
    let container = DependencyContainer.shared
    return AIChatPanel(
        selectionContext: ctx,
        conversationManager: container.conversationManager
    )
}

