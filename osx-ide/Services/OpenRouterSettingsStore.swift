import Foundation

final class OpenRouterSettingsStore {
    private let settingsStore = SettingsStore(userDefaults: .standard)
    private let apiKeyKey = "OpenRouterAPIKey"
    private let modelKey = "OpenRouterModel"
    private let baseURLKey = "OpenRouterBaseURL"
    private let systemPromptKey = "OpenRouterSystemPrompt"
    private let reasoningEnabledKey = "OpenRouterReasoningEnabled"

    func load() -> OpenRouterSettings {
        OpenRouterSettings(
            apiKey: settingsStore.string(forKey: apiKeyKey) ?? "",
            model: settingsStore.string(forKey: modelKey) ?? "",
            baseURL: settingsStore.string(forKey: baseURLKey) ?? OpenRouterSettings.empty.baseURL,
            systemPrompt: settingsStore.string(forKey: systemPromptKey) ?? "",
            reasoningEnabled: settingsStore.bool(forKey: reasoningEnabledKey, default: true)
        )
    }

    func save(_ settings: OpenRouterSettings) {
        settingsStore.set(settings.apiKey, forKey: apiKeyKey)
        settingsStore.set(settings.model, forKey: modelKey)
        settingsStore.set(settings.baseURL, forKey: baseURLKey)
        settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
        settingsStore.set(settings.reasoningEnabled, forKey: reasoningEnabledKey)
    }
}
