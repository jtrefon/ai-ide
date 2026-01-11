import SwiftUI
import Combine

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    let conversationManager: any ConversationManagerProtocol
    @ObservedObject var ui: UIStateManager

    @State private var stateTick: UInt = 0
    @State private var conversationPlan: String? = nil

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(localized("ai_chat.title"))
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                if let selected = currentSelection, !selected.isEmpty {
                    Text(String(format: localized("ai_chat.context_format"), "\(selected.prefix(30))\(selected.count > 30 ? "..." : "")"))
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
                .padding(.horizontal)
            }
            .frame(height: 30)
            .background(Color(NSColor.windowBackgroundColor))

            if shouldShowPlanPanel {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(localized("ai_chat.plan.title"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    MarkdownMessageView(
                        content: conversationPlan ?? localized("ai_chat.plan.empty"),
                        fontSize: ui.fontSize,
                        fontFamily: ui.fontFamily
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(14)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

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
        .onReceive(conversationManager.statePublisher) { _ in
            Task { @MainActor in
                stateTick &+= 1
            }
        }
        .onChange(of: stateTick) { _ in
            Task { @MainActor in
                await refreshConversationPlan()
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

    private var shouldShowPlanPanel: Bool {
        guard let plan = conversationPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty else {
            return false
        }

        if let latestToolMessage = conversationManager.messages.last(where: { $0.isToolExecution }) {
            if latestToolMessage.toolStatus == .executing, latestToolMessage.toolName != "planner" {
                return false
            }
        }

        return true
    }

    @MainActor
    private func refreshConversationPlan() async {
        let conversationId = conversationManager.currentConversationId
        let plan = await ConversationPlanStore.shared.get(conversationId: conversationId)
        conversationPlan = plan
    }
}

#Preview {
    Group {
        let ctx = CodeSelectionContext()
        let container = DependencyContainer()
        AIChatPanel(
            selectionContext: ctx,
            conversationManager: container.conversationManager,
            ui: UIStateManager(uiService: UIService(errorManager: ErrorManager(), eventBus: EventBus()), eventBus: EventBus())
        )
    }
}

