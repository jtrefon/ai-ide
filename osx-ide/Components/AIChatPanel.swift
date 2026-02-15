import SwiftUI
import Combine
import Foundation

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    let conversationManager: any ConversationManagerProtocol
    @ObservedObject var ui: UIStateManager
    @State private var renderRefreshToken: UInt = 0
    @State private var isModelPreviewExpanded: Bool = true

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
                .help(localized("ai_chat.new_conversation_help"))
                .accessibilityIdentifier("AIChatNewConversationButton")
                .padding(.horizontal)
            }
            .frame(height: 30)
            .background(Color(NSColor.windowBackgroundColor))

            ConversationPlanProgressView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                onStopGenerating: {
                    conversationManager.stopGeneration()
                },
                fontSize: ui.fontSize
            )

            if conversationManager.isLiveModelOutputPreviewVisible {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.and.magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Model Output Preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isModelPreviewExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isModelPreviewExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if isModelPreviewExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Raw Stream")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            ScrollView {
                                Text(conversationManager.liveModelOutputPreview.isEmpty ? "No model output yet." : conversationManager.liveModelOutputPreview)
                                    .font(.system(size: max(ui.fontSize - 1, 10), design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)

                            Text("Tool Parsing / Loop Status")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            ScrollView {
                                Text(conversationManager.liveModelOutputStatusPreview.isEmpty
                                     ? "No tool parsing status yet."
                                     : conversationManager.liveModelOutputStatusPreview)
                                    .font(.system(size: max(ui.fontSize - 2, 9), design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 92)
                        }
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
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
