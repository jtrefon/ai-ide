import Foundation

final class KiloCodeSettingsStore: OpenRouterSettingsStoring, @unchecked Sendable {
    static let currentBaseURL = "https://api.kilo.ai/api/openrouter"
    private static let legacyBaseURLs = ["https://api.kilo.ai/api/gateway"]

    private let settingsStore: SettingsStore
    private let apiKeyKey = "KiloCodeAPIKey"
    private let modelKey = "KiloCodeModel"
    private let baseURLKey = "KiloCodeBaseURL"
    private let systemPromptKey = "KiloCodeSystemPrompt"
    private let reasoningModeKey = "KiloCodeReasoningMode"
    private let toolPromptModeKey = "KiloCodeToolPromptMode"
    private let ragEnabledDuringToolLoopKey = "KiloCodeRAGEnabledDuringToolLoop"
    private let environment = ProcessInfo.processInfo.environment

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)) {
        self.settingsStore = settingsStore
    }

    func load(includeApiKey: Bool = true) -> OpenRouterSettings {
        let apiKey: String
        if includeApiKey {
            apiKey = environment["TEST_RUNNER_ENV_HARNESS_KILOCODE_API_KEY"]
                ?? environment["HARNESS_KILOCODE_API_KEY"]
                ?? settingsStore.string(forKey: apiKeyKey)
                ?? ""
        } else {
            apiKey = ""
        }

        let model = harnessOverrideValue(
            testRunnerKey: "TEST_RUNNER_ENV_HARNESS_KILOCODE_MODEL_ID",
            fallbackKey: "HARNESS_KILOCODE_MODEL_ID",
            defaultValue: settingsStore.string(forKey: modelKey) ?? "kilo-auto/balanced"
        )

        let baseURL = harnessOverrideValue(
            testRunnerKey: "TEST_RUNNER_ENV_HARNESS_KILOCODE_BASE_URL",
            fallbackKey: "HARNESS_KILOCODE_BASE_URL",
            defaultValue: resolvedBaseURL(storedValue: settingsStore.string(forKey: baseURLKey))
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

    func save(_ settings: OpenRouterSettings) {
        settingsStore.set(settings.apiKey, forKey: apiKeyKey)
        settingsStore.set(settings.model, forKey: modelKey)
        settingsStore.set(settings.baseURL, forKey: baseURLKey)
        settingsStore.set(settings.systemPrompt, forKey: systemPromptKey)
        settingsStore.set(settings.reasoningMode.rawValue, forKey: reasoningModeKey)
        settingsStore.set(settings.toolPromptMode.rawValue, forKey: toolPromptModeKey)
        settingsStore.set(settings.ragEnabledDuringToolLoop, forKey: ragEnabledDuringToolLoopKey)
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

    private func resolvedBaseURL(storedValue: String?) -> String {
        guard let trimmed = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return Self.currentBaseURL
        }
        if Self.legacyBaseURLs.contains(trimmed) {
            return Self.currentBaseURL
        }
        return trimmed
    }
}
