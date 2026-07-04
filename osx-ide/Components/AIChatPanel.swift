import SwiftUI
import Foundation

private func settingsStore(for provider: RemoteAIProvider) -> ProviderOpenRouterSettingsStore {
    switch provider {
    case .openRouter: return OpenRouterSettingsStore()
    case .alibabaCloud: return AlibabaSettingsStore()
    case .kiloCode: return KiloCodeSettingsStore()
    case .deepSeek: return DeepSeekSettingsStore()
    }
}

private func currentProvider() -> RemoteAIProvider {
    let raw = UserDefaults.standard.string(forKey: "AI.SelectedRemoteProvider") ?? ""
    return RemoteAIProvider(rawValue: raw) ?? .openRouter
}

/// An AI chat panel that uses the user's code selection as context for AI queries and displays responses.
struct AIChatPanel: View {
    @ObservedObject var selectionContext: CodeSelectionContext
    @ObservedObject var conversationManager: ConversationManager
    @ObservedObject var ui: UIStateManager
    @State private var isOfflineMode: Bool = false
    @State private var modelDisplayName: String = "Cloud"
    @State private var reasoningIntensity: ReasoningIntensity = .default
    @StateObject private var modelSearch = ModelSearchViewModel()
    @State private var selectedModelId: String = ""
    @State private var isModelPopover: Bool = false
    @State private var currentSearchModels: [OpenRouterModel] = []
    @State private var hoveredTabId: String?

    private func selectModel(_ model: OpenRouterModel) -> () -> Void {
        { [self] in
            selectedModelId = model.id
            modelSearch.recordSelection(model.id)

            let store = settingsStore(for: currentProvider())
            var settings = store.load(includeApiKey: false)
            settings.model = model.id
            store.save(settings)

            UserDefaults.standard.set(false, forKey: "AI.OfflineModeEnabled")
            NotificationCenter.default.post(name: .localModelOfflineModeDidChange, object: nil)
            modelDisplayName = model.name ?? model.id
            isModelPopover = false
            modelSearch.searchQuery = ""
        }
    }

    @ViewBuilder
    private func modelRowLabel(_ model: OpenRouterModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name ?? model.id)
                    .font(.body)
                Text(model.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isOfflineMode && selectedModelId == model.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        let searchModels = currentSearchModels
        let displayedTabs = conversationManager.conversationTabs.isEmpty
            ? [ConversationTabItem(id: conversationManager.currentConversationId, title: "Chat 1")]
            : conversationManager.conversationTabs

        VStack(alignment: .leading, spacing: 0) {
            // Tabs header
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(displayedTabs) { tab in
                            let isActive = tab.id == conversationManager.currentConversationId
                            let isHovered = hoveredTabId == tab.id
                            Button {
                                conversationManager.switchConversation(to: tab.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(tab.title)
                                        .lineLimit(1)
                                        .font(.body)
                                        .foregroundColor(isActive ? .primary : .secondary)
                                    if displayedTabs.count > 1 {
                                        Button {
                                            conversationManager.closeConversation(id: tab.id)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .opacity(isHovered ? 1 : 0)
                                        .frame(width: 16, height: 16)
                                        .help("Close conversation")
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(AppConstants.Color.surfaceCard)
                                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 5))
                                    } else {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isHovered
                                                ? AppConstants.Color.surfaceCard.opacity(0.15)
                                                : Color.clear)
                                            .strokeBorder(
                                                Color(nsColor: .separatorColor).opacity(isHovered ? 0.35 : 0.2),
                                                lineWidth: 1
                                            )
                                    }
                                }
                                .animation(.easeInOut(duration: 0.15), value: isHovered)
                                .animation(.easeInOut(duration: 0.15), value: isActive)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering { hoveredTabId = tab.id }
                                else if hoveredTabId == tab.id { hoveredTabId = nil }
                            }
                            .accessibilityIdentifier("ConversationTab_\(tab.id)")
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.vertical, 2)
                }

                Button(action: {
                    conversationManager.startNewConversation()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(localized("ai_chat.new_conversation_help"))
                .accessibilityIdentifier(AccessibilityID.aiChatNewConversationButton)
                .padding(.trailing, 6)
            }
            .frame(height: 32)
            .padding(.horizontal, 4)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.separator),
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
                    .foregroundStyle(.red)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.aiChatPanel)
        .nativeGlassBackground(.panel, cornerRadius: 0)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(localized("ai_chat.mode"), selection: modeBinding) {
                    ForEach(AIMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Button {
                    isModelPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOfflineMode ? "network.slash" : "cloud.fill")
                        Text("\(modelDisplayName) [\(intensityShortLabel(reasoningIntensity))]")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderless)
                .help(modelDisplayName)
                .popover(isPresented: $isModelPopover, arrowEdge: .bottom) {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search models...", text: $modelSearch.searchQuery)
                                .textFieldStyle(.plain)
                                .font(.body)
                            if !modelSearch.searchQuery.isEmpty {
                                Button { modelSearch.searchQuery = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)

                        Divider()

                        ScrollView {
                            ScrollViewReader { _ in
                                LazyVStack(spacing: 0) {
                                    ForEach(0..<searchModels.count, id: \.self) { index in
                                        let model = searchModels[index]
                                        Button(action: selectModel(model), label: { modelRowLabel(model) })
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Button("Local Model") {
                                Task {
                                    let store = LocalModelSelectionStore()
                                    await store.setSelectedModelId(quickSelectModel.id)
                                    await store.setOfflineModeEnabled(true)
                                }
                                isModelPopover = false
                                modelSearch.searchQuery = ""
                            }
                            .buttonStyle(.link)

                            Spacer()

                            Menu("Reasoning: \(intensityShortLabel(reasoningIntensity))") {
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
                            .menuStyle(.borderlessButton)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .frame(width: 320, height: 400)
                }
            }
        }
        }
        .onAppear {
            refreshModelState()
            Task {
                let baseURL = settingsStore(for: currentProvider()).load(includeApiKey: false).baseURL
                await modelSearch.loadModels(baseURL: baseURL)
            }
        }
        .onChange(of: modelSearch.searchQuery) { _, _ in
            currentSearchModels = modelSearch.displayModels
        }
        .onChange(of: modelSearch.displayModels.count) { _, _ in
            currentSearchModels = modelSearch.displayModels
        }
        .onReceive(NotificationCenter.default.publisher(for: .localModelOfflineModeDidChange)) { _ in
            refreshModelState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localModelSelectionDidChange)) { _ in
            refreshModelState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteProviderDidChange)) { _ in
            refreshModelState()
            Task {
                let baseURL = settingsStore(for: currentProvider()).load(includeApiKey: false).baseURL
                await modelSearch.loadModels(baseURL: baseURL)
            }
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
            let provider = currentProvider()
            let store = settingsStore(for: provider)
            let settings = store.load(includeApiKey: false)
            if !settings.model.isEmpty {
                modelDisplayName = settings.model
            } else {
                modelDisplayName = provider.displayName
            }
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

    private var quickSelectModel: LocalModelDefinition {
        LocalModelCatalog.defaultModel
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
            let isInsufficientBalance = issue.statusCode == 402
            let accentColor: Color = isInsufficientBalance ? .red : .orange
            let iconName = isInsufficientBalance ? "exclamationmark.octagon.fill" :
                (issue.cooldownUntil == nil ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundStyle(accentColor)
                    Text(providerIssueHeadline(issue))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if let countdownText {
                        Text(countdownText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isInsufficientBalance {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("OpenRouter.ai/settings/credits")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(0.25), lineWidth: 1)
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
