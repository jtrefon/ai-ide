import Foundation

final class OpenRouterSettingsStore {
    private let settingsStore = SettingsStore(userDefaults: .standard)
    private let apiKeyKey = "OpenRouterAPIKey"
    private let modelKey = "OpenRouterModel"
    private let baseURLKey = "OpenRouterBaseURL"
    private let systemPromptKey = "OpenRouterSystemPrompt"
    private let reasoningEnabledKey = "OpenRouterReasoningEnabled"

    private let keychainStore = KeychainStore(service: "tdc.osx-ide.openrouter")
    private let keychainAccount = "apiKey"

    private func migrateApiKeyFromUserDefaultsIfNeeded() {
        guard let legacy = settingsStore.string(forKey: apiKeyKey), !legacy.isEmpty else { return }
        do {
            let existingKeychainValue = try keychainStore.readPassword(account: keychainAccount)
            if existingKeychainValue?.isEmpty != false {
                try keychainStore.savePassword(legacy, account: keychainAccount)
            }
            settingsStore.removeObject(forKey: apiKeyKey)
        } catch {
        }
    }

    func load() -> OpenRouterSettings {
        migrateApiKeyFromUserDefaultsIfNeeded()
        let apiKey = (try? keychainStore.readPassword(account: keychainAccount)) ?? ""
        return OpenRouterSettings(
            apiKey: apiKey,
            model: settingsStore.string(forKey: modelKey) ?? "",
            baseURL: settingsStore.string(forKey: baseURLKey) ?? OpenRouterSettings.empty.baseURL,
            systemPrompt: settingsStore.string(forKey: systemPromptKey) ?? "",
            reasoningEnabled: settingsStore.bool(forKey: reasoningEnabledKey, default: true)
        )
    }

    func save(_ settings: OpenRouterSettings) {
        do {
            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keychainStore.deletePassword(account: keychainAccount)
            } else {
                try keychainStore.savePassword(settings.apiKey, account: keychainAccount)
            }
        } catch {
        }
        settingsStore.set(settings.model, forKey: modelKey)
        settingsStore.set(settings.baseURL, forKey: baseURLKey)
        settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
        settingsStore.set(settings.reasoningEnabled, forKey: reasoningEnabledKey)
    }
}
