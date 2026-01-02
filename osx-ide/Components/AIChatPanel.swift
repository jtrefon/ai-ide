import SwiftUI
import Combine

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    let conversationManager: any ConversationManagerProtocol
    @ObservedObject var ui: UIStateManager

    @State private var stateTick: UInt = 0

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
            .background(Color(NSColor.windowBackgroundColor))
            
            // Messages list
            MessageListView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
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
                
                Picker("Mode", selection: modeBinding) {
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
        .onReceive(conversationManager.statePublisher) { _ in
            DispatchQueue.main.async {
                stateTick &+= 1
            }
        }
        .animation(nil, value: stateTick)
        .accessibilityIdentifier("AIChatPanel")
        .background(Color(NSColor.controlBackgroundColor))
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
        conversationManager.currentInput = conversationManager.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationManager.sendMessage(context: context)
    }
}

#Preview {
    Group {
        let ctx = CodeSelectionContext()
        let container = DependencyContainer.shared
        AIChatPanel(
            selectionContext: ctx,
            conversationManager: container.conversationManager,
            ui: UIStateManager(uiService: UIService(errorManager: ErrorManager()))
        )
    }
}

