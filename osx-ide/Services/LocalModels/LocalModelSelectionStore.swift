import Foundation

extension Notification.Name {
    static let localModelOfflineModeDidChange = Notification.Name("LocalModelOfflineModeDidChange")
    static let localModelSelectionDidChange = Notification.Name("LocalModelSelectionDidChange")
}

actor LocalModelSelectionStore {
    private let settingsStore: SettingsStore
    private let selectedModelKey = "LocalModel.SelectedId"
    private let offlineModeEnabledKey = "AI.OfflineModeEnabled"

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)) {
        self.settingsStore = settingsStore
    }

    func selectedModelId() -> String {
        (settingsStore.string(forKey: selectedModelKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setSelectedModelId(_ modelId: String) {
        let trimmedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedModelId() != trimmedModelId else { return }
        settingsStore.set(trimmedModelId, forKey: selectedModelKey)
        NotificationCenter.default.post(
            name: .localModelSelectionDidChange,
            object: nil,
            userInfo: ["modelId": trimmedModelId]
        )
    }

    func isOfflineModeEnabled() -> Bool {
        settingsStore.bool(forKey: offlineModeEnabledKey, default: false)
    }

    func setOfflineModeEnabled(_ enabled: Bool) {
        guard isOfflineModeEnabled() != enabled else { return }
        settingsStore.set(enabled, forKey: offlineModeEnabledKey)
        NotificationCenter.default.post(
            name: .localModelOfflineModeDidChange,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
}
