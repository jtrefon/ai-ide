import Foundation

final class LocalModelSelectionStore: @unchecked Sendable {
    private let settingsStore: SettingsStore
    private let selectedModelKey = "LocalModel.SelectedId"
    private let offlineModeEnabledKey = "AI.OfflineModeEnabled"

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: .standard)) {
        self.settingsStore = settingsStore
    }

    func selectedModelId() -> String {
        (settingsStore.string(forKey: selectedModelKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setSelectedModelId(_ modelId: String) {
        settingsStore.set(modelId, forKey: selectedModelKey)
    }

    func isOfflineModeEnabled() -> Bool {
        settingsStore.bool(forKey: offlineModeEnabledKey, default: false)
    }

    func setOfflineModeEnabled(_ enabled: Bool) {
        settingsStore.set(enabled, forKey: offlineModeEnabledKey)
    }
}
