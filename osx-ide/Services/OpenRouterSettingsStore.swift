import Foundation

protocol OpenRouterSettingsLoading {
    func load(includeApiKey: Bool) -> OpenRouterSettings
}

final class OpenRouterSettingsStore: OpenRouterSettingsLoading, @unchecked Sendable {
    private let settingsStore: SettingsStore
    private let apiKeyKey = "OpenRouterAPIKey"
    private let modelKey = "OpenRouterModel"
    private let baseURLKey = "OpenRouterBaseURL"
    private let systemPromptKey = "OpenRouterSystemPrompt"
    private let reasoningEnabledKey = "OpenRouterReasoningEnabled"
    private let toolPromptModeKey = "OpenRouterToolPromptMode"
    private let ragEnabledDuringToolLoopKey = "OpenRouterRAGEnabledDuringToolLoop"

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)) {
        self.settingsStore = settingsStore
    }

    // NOTE: Keychain removed due to UX issues (constant password prompts)
    // Using UserDefaults for API key storage - macOS provides sufficient security
    
    func load(includeApiKey: Bool = true) -> OpenRouterSettings {
        let apiKey: String
        if includeApiKey {
            // Simple UserDefaults storage - no keychain prompts
            apiKey = settingsStore.string(forKey: apiKeyKey) ?? ""
        } else {
            apiKey = ""
        }
        return OpenRouterSettings(
            apiKey: apiKey,
            model: settingsStore.string(forKey: modelKey) ?? "",
            baseURL: settingsStore.string(forKey: baseURLKey) ?? OpenRouterSettings.empty.baseURL,
            systemPrompt: settingsStore.string(forKey: systemPromptKey) ?? "",
            reasoningEnabled: settingsStore.bool(forKey: reasoningEnabledKey, default: true),
            toolPromptMode: ToolPromptMode(
                rawValue: settingsStore.string(forKey: toolPromptModeKey) ?? ""
            ) ?? .fullStatic,
            ragEnabledDuringToolLoop: settingsStore.bool(
                forKey: ragEnabledDuringToolLoopKey,
                default: OpenRouterSettings.empty.ragEnabledDuringToolLoop
            )
        )
    }

    func save(_ settings: OpenRouterSettings) {
        // Store API key in UserDefaults - no keychain prompts
        settingsStore.set(settings.apiKey, forKey: apiKeyKey)
        settingsStore.set(settings.model, forKey: modelKey)
        settingsStore.set(settings.baseURL, forKey: baseURLKey)
        settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
        settingsStore.set(settings.reasoningEnabled, forKey: reasoningEnabledKey)
        settingsStore.set(settings.toolPromptMode.rawValue, forKey: toolPromptModeKey)
        settingsStore.set(settings.ragEnabledDuringToolLoop, forKey: ragEnabledDuringToolLoopKey)
    }
}
