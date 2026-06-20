import SwiftUI
import Combine
import Foundation

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    let conversationManager: any ConversationManagerProtocol
    @ObservedObject var ui: UIStateManager
    @State private var renderRefreshToken: UInt = 0
    @State private var isOfflineMode: Bool = false
    @State private var modelDisplayName: String = "Cloud"
    @State private var reasoningIntensity: ReasoningIntensity = .default

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

            MessageListView(
                messages: conversationManager.messages,
                isSending: conversationManager.isSending,
                fontSize: ui.fontSize,
                fontFamily: ui.fontFamily
            )
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .layoutPriority(1)
            .clipped()

            if let providerIssue = conversationManager.providerIssue {
                providerIssueBanner(providerIssue)
            }

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

                Menu {
                    Section("Cloud") {
                        ForEach(RemoteAIProvider.allCases, id: \.self) { provider in
                            Button {
                                Task {
                                    let store = AIProviderSelectionStore()
                                    await store.setSelectedRemoteProvider(provider)
                                    UserDefaults.standard.set(false, forKey: "AI.OfflineModeEnabled")
                                    NotificationCenter.default.post(name: .localModelOfflineModeDidChange, object: nil)
                                }
                            } label: {
                                HStack {
                                    Text(provider.displayName)
                                    if !isOfflineMode && modelDisplayName == provider.displayName {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Section("Local") {
                        Button {
                            Task {
                                let store = LocalModelSelectionStore()
                                await store.setSelectedModelId(gemmaE4bModel.id)
                                await store.setOfflineModeEnabled(true)
                            }
                        } label: {
                            HStack {
                                Text(gemmaE4bModel.displayName)
                                if isOfflineMode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Section("Reasoning") {
                        ForEach(ReasoningIntensity.allCases, id: \.self) { intensity in
                            Button {
                                UserDefaults.standard.set(intensity.rawValue, forKey: "AI.ReasoningIntensity")
                                reasoningIntensity = intensity
                            } label: {
                                HStack {
                                    Text(intensityLabel(intensity))
                                    if reasoningIntensity == intensity {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOfflineMode ? "network.slash" : "cloud.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(modelDisplayName) [\(intensityShortLabel(reasoningIntensity))]")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(5)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.aiChatPanel)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            refreshModelState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localModelOfflineModeDidChange)) { _ in
            refreshModelState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localModelSelectionDidChange)) { _ in
            refreshModelState()
        }
        .onReceive(conversationManager.statePublisher) { _ in
            renderRefreshToken &+= 1
        }
    }

    private func refreshModelState() {
        let defaults = UserDefaults.standard
        isOfflineMode = defaults.bool(forKey: "AI.OfflineModeEnabled")
        reasoningIntensity = ReasoningIntensity.current
        if isOfflineMode {
            let modelId = defaults.string(forKey: "LocalModel.SelectedId") ?? ""
            modelDisplayName = LocalModelCatalog.model(id: modelId)?.displayName ?? modelId
        } else {
            let raw = defaults.string(forKey: "AI.SelectedRemoteProvider") ?? ""
            modelDisplayName = RemoteAIProvider(rawValue: raw)?.displayName ?? "Cloud"
        }
    }

    private func intensityLabel(_ intensity: ReasoningIntensity) -> String {
        switch intensity {
        case .min: return "Min"
        case .med: return "Med"
        case .max: return "Max"
        }
    }

    private func intensityShortLabel(_ intensity: ReasoningIntensity) -> String {
        switch intensity {
        case .min: return "Min"
        case .med: return "Med"
        case .max: return "Max"
        }
    }

    private var gemmaE4bModel: LocalModelDefinition {
        LocalModelCatalog.model(id: "mlx-community/gemma-4-e4b-it-4bit@62b0e4e")!
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

    @ViewBuilder
    private func providerIssueBanner(_ issue: ConversationProviderIssueState) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let countdownText = providerIssueCountdownText(issue, now: context.date)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: issue.cooldownUntil == nil ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                    Text(providerIssueHeadline(issue))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer(minLength: 0)
                    if let countdownText {
                        Text(countdownText)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                Text(issue.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.aiChatProviderIssueBanner)
        }
    }

    private func providerIssueHeadline(_ issue: ConversationProviderIssueState) -> String {
        if let statusCode = issue.statusCode {
            return "\(issue.providerName) \(issue.issueType) (HTTP \(statusCode))"
        }

        return "\(issue.providerName) \(issue.issueType)"
    }

    private func providerIssueCountdownText(
        _ issue: ConversationProviderIssueState,
        now: Date
    ) -> String? {
        guard let cooldownUntil = issue.cooldownUntil else {
            return nil
        }

        let remainingSeconds = max(0, Int(ceil(cooldownUntil.timeIntervalSince(now))))
        guard remainingSeconds > 0 else {
            return "Retrying now"
        }

        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "Retry in %02d:%02d", minutes, seconds)
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
