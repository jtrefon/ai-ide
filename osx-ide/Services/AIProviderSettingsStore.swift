import Foundation

final class AIProviderSettingsStore {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: .standard)) {
        self.settingsStore = settingsStore
    }

    func load() -> AIProvider {
        let raw = settingsStore.string(forKey: AppConstantsStorage.aiProviderKey) ?? AIProvider.remote.rawValue
        return AIProvider(rawValue: raw) ?? .remote
    }

    func save(_ provider: AIProvider) {
        settingsStore.set(provider.rawValue, forKey: AppConstantsStorage.aiProviderKey)
    }
}
