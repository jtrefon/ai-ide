import SwiftUI
import Foundation

private func settingsStore(for provider: RemoteAIProvider) -> ProviderOpenRouterSettingsStore {
    switch provider {
    case .openRouter: return OpenRouterSettingsStore()
    case .alibabaCloud: return AlibabaSettingsStore()
    case .kiloCode: return KiloCodeSettingsStore()
    case .deepSeek: return DeepSeekSettingsStore()
    case .openCodeGo: return OpenCodeGoSettingsStore()
    case .openCodeGoSubscription: return OpenCodeGoSubscriptionSettingsStore()
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
    @State private var hoveredModelId: String?
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
        HStack(spacing: AppConstants.Layout.spacingSm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name ?? model.id)
                    .font(.body)
                Text(model.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: AppConstants.Layout.spacingSm)
            if !isOfflineMode && selectedModelId == model.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, AppConstants.Layout.spacingMd)
        .padding(.vertical, AppConstants.Layout.rowVerticalPadding)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        let displayedTabs = conversationManager.conversationTabs.isEmpty
            ? [ConversationTabItem(id: conversationManager.currentConversationId, title: "Chat 1")]
            : conversationManager.conversationTabs

        VStack(alignment: .leading, spacing: 0) {
            // Tabs header
            HStack(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(displayedTabs) { tab in
                        let isActive = tab.id == conversationManager.currentConversationId
                        let isHovered = hoveredTabId == tab.id
                        Button {
                            conversationManager.switchConversation(to: tab.id)
                        } label: {
                            HStack(spacing: 5) {
                                Spacer(minLength: 4)

                                Image(systemName: "bubble.left.and.text")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, height: 14)

                                Text(tab.title)
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                                    .foregroundColor(isActive ? .primary : .secondary)

                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                if isActive {
                                    Capsule()
                                        .glassEffect(.regular, in: Capsule())
                                } else {
                                    Capsule()
                                        .fill(isHovered
                                            ? Color(nsColor: .windowBackgroundColor).opacity(0.5)
                                            : Color(nsColor: .windowBackgroundColor).opacity(0.35))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 80)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) {
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
                                .frame(width: 24, height: 24)
                                .padding(.leading, 4)
                                .help("Close conversation")
                            }
                        }
                        .onHover { hovering in
                            if hovering { hoveredTabId = tab.id }
                            else if hoveredTabId == tab.id { hoveredTabId = nil }
                        }
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                        .animation(.easeInOut(duration: 0.15), value: isActive)
                        .accessibilityIdentifier("ConversationTab_\(tab.id)")
                    }
                }
                .padding(.leading, AppConstants.Layout.spacingXS)
                .padding(.vertical, AppConstants.Layout.spacingXXS)

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
                .padding(.trailing, AppConstants.Layout.spacingSm)
            }
            .frame(height: AppConstants.Layout.headerHeight)
            .padding(.horizontal, AppConstants.Layout.spacingXS)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(AppConstants.Color.separatorDefault),
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
                },
                onStop: {
                    conversationManager.stopGeneration()
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.aiChatPanel)
        .nativeGlassBackground(.panel, cornerRadius: 0)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(AIMode.allCases) { mode in
                        Button(mode.rawValue) {
                            modeBinding.wrappedValue = mode
                        }
                    }
                } label: {
                    CapsuleDropdownLabel {
                        Text(modeBinding.wrappedValue.rawValue)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                // Model selector — functional dropdown via popover so the search field and
                // model list stay interactive. Internal margins keep content off the pill border.
                Button {
                    isModelPopover.toggle()
                } label: {
                    CapsuleDropdownLabel {
                        Image(systemName: isOfflineMode ? "network.slash" : "cloud.fill")
                        Text("\(modelDisplayName) [\(intensityShortLabel(reasoningIntensity))]")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $isModelPopover, arrowEdge: .bottom) {
                    modelPickerPopover
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

    @ViewBuilder
    private var modelPickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppConstants.Layout.spacingXS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $modelSearch.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !modelSearch.searchQuery.isEmpty {
                    Button {
                        modelSearch.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppConstants.Layout.spacingMd)
            .padding(.vertical, AppConstants.Layout.spacingSm)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(currentSearchModels, id: \.id) { model in
                        Button(action: selectModel(model)) {
                            modelRowLabel(model)
                        }
                        .buttonStyle(.plain)
                        .onHover { isOver in
                            hoveredModelId = isOver
                                ? model.id
                                : (hoveredModelId == model.id ? nil : hoveredModelId)
                        }
                        .background(
                            hoveredModelId == model.id
                                ? RoundedRectangle(cornerRadius: AppConstants.Layout.cornerSm, style: .continuous)
                                    .fill(AppConstants.Color.accentSubtle)
                                : RoundedRectangle(cornerRadius: AppConstants.Layout.cornerSm, style: .continuous)
                                    .fill(Color.clear)
                        )
                    }
                }
                .padding(.vertical, AppConstants.Layout.spacingXS)
            }

            Divider()

            HStack(spacing: AppConstants.Layout.spacingSm) {
                Button {
                    Task {
                        let store = LocalModelSelectionStore()
                        await store.setSelectedModelId(quickSelectModel.id)
                        await store.setOfflineModeEnabled(true)
                    }
                    isModelPopover = false
                    modelSearch.searchQuery = ""
                } label: {
                    HStack(spacing: AppConstants.Layout.spacingXS) {
                        Image(systemName: "cpu")
                        Text("Local Model")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Menu {
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
                } label: {
                    HStack(spacing: AppConstants.Layout.spacingXS) {
                        Text("Reasoning: \(intensityShortLabel(reasoningIntensity))")
                        Image(systemName: "chevron.down")
                            .font(.system(size: AppConstants.Layout.controlChevronSize))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderedButton)
            }
            .padding(.horizontal, AppConstants.Layout.spacingMd)
            .padding(.vertical, AppConstants.Layout.spacingSm)
        }
        .frame(
            width: AppConstants.Overlay.modelPopoverWidth,
            height: AppConstants.Overlay.modelPopoverHeight
        )
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
            let isNetworkOffline = issue.issueType == "Network offline"
            // 429/rate-limit uses orange; network connectivity uses a distinct blue
            // so the two transient issues are visually separable.
            let accentColor: Color = isInsufficientBalance ? AppConstants.Color.alertError : (isNetworkOffline ? AppConstants.Color.alertInfo : AppConstants.Color.alertWarning)
            let iconName: String = isInsufficientBalance ? "exclamationmark.octagon.fill" :
                (isNetworkOffline ? "wifi.slash" :
                    (issue.cooldownUntil == nil ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark"))

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
            .padding(.horizontal, AppConstants.Layout.spacingMd)
            .padding(.vertical, AppConstants.Layout.spacingSm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.Layout.cornerMd)
                    .stroke(accentColor.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, AppConstants.Layout.spacingSm)
            .padding(.top, AppConstants.Layout.spacingSm)
            .padding(.bottom, AppConstants.Layout.spacingXS)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.aiChatProviderIssueBanner)
        }
    }

    private func providerIssueHeadline(_ issue: ConversationProviderIssueState) -> String {
        // Network connectivity is provider-agnostic — never quote a specific
        // provider (e.g. "OpenRouter") for an offline/timeout condition.
        if issue.issueType == "Network offline" {
            if let statusCode = issue.statusCode {
                return "Network offline (HTTP \(statusCode))"
            }
            return "Network offline"
        }

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
