import Foundation

protocol OpenRouterSettingsLoading {
    func load(includeApiKey: Bool) -> OpenRouterSettings
}

final class OpenRouterSettingsStore: OpenRouterSettingsLoading {
    private let settingsStore = SettingsStore(userDefaults: .standard)
    private let apiKeyKey = "OpenRouterAPIKey"
    private let apiKeyMigrationCompleteKey = "OpenRouterAPIKeyKeychainMigrationComplete"
    private let modelKey = "OpenRouterModel"
    private let baseURLKey = "OpenRouterBaseURL"
    private let systemPromptKey = "OpenRouterSystemPrompt"
    private let reasoningEnabledKey = "OpenRouterReasoningEnabled"

    private let keychainStore = KeychainStore(service: "tdc.osx-ide.openrouter")
    private let keychainAccount = "apiKey"

    private var shouldUseKeychain: Bool {
        ProcessInfo.processInfo.environment["XCUI_TESTING"] != "1"
            && ProcessInfo.processInfo.environment["OSXIDE_DISABLE_KEYCHAIN"] != "1"
    }

    private func migrateApiKeyFromUserDefaultsIfNeeded() {
        if settingsStore.bool(forKey: apiKeyMigrationCompleteKey, default: false) {
            return
        }
        guard let legacy = settingsStore.string(forKey: apiKeyKey), !legacy.isEmpty else { return }
        do {
            let existingKeychainValue = try keychainStore.readPassword(account: keychainAccount)
            if existingKeychainValue?.isEmpty != false {
                try keychainStore.savePassword(legacy, account: keychainAccount)
            }
            settingsStore.removeObject(forKey: apiKeyKey)
            settingsStore.set(true, forKey: apiKeyMigrationCompleteKey)
        } catch {
            Task {
                await AppLogger.shared.error(
                    category: .ai,
                    message: "openrouter.keychain_migration_failed",
                    context: AppLogger.LogCallContext(metadata: [
                        "error": error.localizedDescription
                    ])
                )
            }
            settingsStore.set(true, forKey: apiKeyMigrationCompleteKey)
        }
    }

    func load(includeApiKey: Bool = true) -> OpenRouterSettings {
        if includeApiKey, shouldUseKeychain {
            migrateApiKeyFromUserDefaultsIfNeeded()
        }

        let apiKey: String
        if includeApiKey, shouldUseKeychain {
            apiKey = (try? keychainStore.readPassword(account: keychainAccount)) ?? ""
        } else {
            apiKey = ""
        }
        return OpenRouterSettings(
            apiKey: apiKey,
            model: settingsStore.string(forKey: modelKey) ?? "",
            baseURL: settingsStore.string(forKey: baseURLKey) ?? OpenRouterSettings.empty.baseURL,
            systemPrompt: settingsStore.string(forKey: systemPromptKey) ?? "",
            reasoningEnabled: settingsStore.bool(forKey: reasoningEnabledKey, default: true)
        )
    }

    func save(_ settings: OpenRouterSettings) {
        guard shouldUseKeychain else {
            settingsStore.set(settings.model, forKey: modelKey)
            settingsStore.set(settings.baseURL, forKey: baseURLKey)
            settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
            settingsStore.set(settings.reasoningEnabled, forKey: reasoningEnabledKey)
            return
        }

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
