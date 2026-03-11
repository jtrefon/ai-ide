import Foundation

final class AlibabaSettingsStore: OpenRouterSettingsStoring, @unchecked Sendable {
    private let settingsStore: SettingsStore
    private let apiKeyKey = "AlibabaAPIKey"
    private let modelKey = "AlibabaModel"
    private let baseURLKey = "AlibabaBaseURL"
    private let systemPromptKey = "AlibabaSystemPrompt"
    private let reasoningModeKey = "AlibabaReasoningMode"
    private let toolPromptModeKey = "AlibabaToolPromptMode"
    private let ragEnabledDuringToolLoopKey = "AlibabaRAGEnabledDuringToolLoop"
    private let environment = ProcessInfo.processInfo.environment

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)) {
        self.settingsStore = settingsStore
    }

    func load(includeApiKey: Bool = true) -> OpenRouterSettings {
        let apiKey: String
        if includeApiKey {
            apiKey = environment["TEST_RUNNER_ENV_HARNESS_ALIBABA_API_KEY"]
                ?? environment["HARNESS_ALIBABA_API_KEY"]
                ?? settingsStore.string(forKey: apiKeyKey)
                ?? ""
        } else {
            apiKey = ""
        }

        let model = harnessOverrideValue(
            testRunnerKey: "TEST_RUNNER_ENV_HARNESS_ALIBABA_MODEL_ID",
            fallbackKey: "HARNESS_ALIBABA_MODEL_ID",
            defaultValue: settingsStore.string(forKey: modelKey) ?? "qwen-plus"
        )

        let baseURL = harnessOverrideValue(
            testRunnerKey: "TEST_RUNNER_ENV_HARNESS_ALIBABA_BASE_URL",
            fallbackKey: "HARNESS_ALIBABA_BASE_URL",
            defaultValue: settingsStore.string(forKey: baseURLKey) ?? "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        )

        return OpenRouterSettings(
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            systemPrompt: settingsStore.string(forKey: systemPromptKey) ?? "",
            reasoningMode: ReasoningMode(
                rawValue: settingsStore.string(forKey: reasoningModeKey) ?? ""
            ) ?? .modelAndAgent,
            toolPromptMode: ToolPromptMode(
                rawValue: settingsStore.string(forKey: toolPromptModeKey) ?? ""
            ) ?? .fullStatic,
            ragEnabledDuringToolLoop: settingsStore.bool(
                forKey: ragEnabledDuringToolLoopKey,
                default: true
            )
        )
    }

    private func harnessOverrideValue(
        testRunnerKey: String,
        fallbackKey: String,
        defaultValue: String
    ) -> String {
        if let value = environment[testRunnerKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        if let value = environment[fallbackKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return defaultValue
    }

    func save(_ settings: OpenRouterSettings) {
        settingsStore.set(settings.apiKey, forKey: apiKeyKey)
        settingsStore.set(settings.model, forKey: modelKey)
        settingsStore.set(settings.baseURL, forKey: baseURLKey)
        settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
        settingsStore.set(settings.reasoningMode.rawValue, forKey: reasoningModeKey)
        settingsStore.set(settings.toolPromptMode.rawValue, forKey: toolPromptModeKey)
        settingsStore.set(settings.ragEnabledDuringToolLoop, forKey: ragEnabledDuringToolLoopKey)
    }
}
