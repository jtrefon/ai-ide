import Foundation

final class LocalModelSettingsStore {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: .standard)) {
        self.settingsStore = settingsStore
    }

    func load() -> LocalModelSettings {
        let legacyMaxOutputTokens = settingsStore.int(
            forKey: AppConstantsStorage.localModelMaxOutputTokensKey,
            default: LocalModelSettings.default.maxAnswerTokens
        )
        let maxAnswerTokens = settingsStore.int(
            forKey: AppConstantsStorage.localModelMaxAnswerTokensKey,
            default: legacyMaxOutputTokens
        )
        let maxReasoningTokens = settingsStore.int(
            forKey: AppConstantsStorage.localModelMaxReasoningTokensKey,
            default: LocalModelSettings.default.maxReasoningTokens
        )

        let temperatureRaw = settingsStore.double(forKey: AppConstantsStorage.localModelTemperatureKey)
        let temperature = temperatureRaw == 0
            ? LocalModelSettings.default.temperature
            : temperatureRaw

        return LocalModelSettings(
            isEnabled: settingsStore.bool(forKey: AppConstantsStorage.localModelEnabledKey, default: LocalModelSettings.default.isEnabled),
            selectedModelId: settingsStore.string(forKey: AppConstantsStorage.localModelSelectedModelIdKey)
                ?? LocalModelSettings.default.selectedModelId,
            quantization: LocalModelQuantization(
                rawValue: settingsStore.string(forKey: AppConstantsStorage.localModelQuantizationKey) ?? LocalModelSettings.default.quantization.rawValue
            ) ?? LocalModelSettings.default.quantization,
            allowRemoteFallback: settingsStore.bool(
                forKey: AppConstantsStorage.localModelAllowRemoteFallbackKey,
                default: LocalModelSettings.default.allowRemoteFallback
            ),
            contextBudgetTokens: settingsStore.int(
                forKey: AppConstantsStorage.localModelContextBudgetTokensKey,
                default: LocalModelSettings.default.contextBudgetTokens
            ),
            maxAnswerTokens: maxAnswerTokens,
            maxReasoningTokens: maxReasoningTokens,
            temperature: max(0.0, min(2.0, temperature))
        )
    }

    func save(_ settings: LocalModelSettings) {
        settingsStore.set(settings.isEnabled, forKey: AppConstantsStorage.localModelEnabledKey)
        settingsStore.set(settings.selectedModelId, forKey: AppConstantsStorage.localModelSelectedModelIdKey)
        settingsStore.set(settings.quantization.rawValue, forKey: AppConstantsStorage.localModelQuantizationKey)
        settingsStore.set(settings.allowRemoteFallback, forKey: AppConstantsStorage.localModelAllowRemoteFallbackKey)
        settingsStore.set(settings.contextBudgetTokens, forKey: AppConstantsStorage.localModelContextBudgetTokensKey)
        settingsStore.set(settings.maxAnswerTokens, forKey: AppConstantsStorage.localModelMaxAnswerTokensKey)
        settingsStore.set(settings.maxReasoningTokens, forKey: AppConstantsStorage.localModelMaxReasoningTokensKey)
        settingsStore.set(settings.temperature, forKey: AppConstantsStorage.localModelTemperatureKey)
    }
}
