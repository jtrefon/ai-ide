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
        let displayedTabs = conversationManager.conversationTabs.isEmpty
            ? [ConversationTabItem(id: conversationManager.currentConversationId, title: "Chat 1")]
            : conversationManager.conversationTabs

        VStack(alignment: .leading, spacing: 0) {
            // Tabs header
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(displayedTabs) { tab in
                            HStack(spacing: 6) {
                                Button {
                                    conversationManager.switchConversation(to: tab.id)
                                } label: {
                                    Text(tab.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(tab.id == conversationManager.currentConversationId ? .white : .primary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                if displayedTabs.count > 1 {
                                    Button {
                                        conversationManager.closeConversation(id: tab.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(tab.id == conversationManager.currentConversationId ? .white.opacity(0.85) : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("ConversationTabCloseButton_\(tab.id)")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(tab.id == conversationManager.currentConversationId ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                            )
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("ConversationTab_\(tab.id)")
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 4)
                }

                Button(action: {
                    conversationManager.startNewConversation()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(localized("ai_chat.new_conversation_help"))
                .accessibilityLabel(localized("ai_chat.new_conversation_help"))
                .accessibilityIdentifier(AccessibilityID.aiChatNewConversationButton)
                .padding(.trailing, 8)
            }
            .frame(height: 34)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.18)),
                alignment: .bottom
            )

            ConversationPlanProgressView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                onStopGenerating: {
                    conversationManager.stopGeneration()
                },
                fontSize: ui.fontSize
            )

            MessageListView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .layoutPriority(1)
            .clipped()

            // Error display
            if let error = conversationManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.aiChatPanel)
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
