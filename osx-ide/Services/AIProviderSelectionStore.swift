import Foundation

enum RemoteAIProvider: String, CaseIterable, Equatable {
    case openRouter
    case alibabaCloud

    var displayName: String {
        switch self {
        case .openRouter:
            return "OpenRouter"
        case .alibabaCloud:
            return "Alibaba Cloud"
        }
    }
}

actor AIProviderSelectionStore {
    private let settingsStore: SettingsStore
    private let selectedRemoteProviderKey = "AI.SelectedRemoteProvider"

    init(settingsStore: SettingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)) {
        self.settingsStore = settingsStore
    }

    func selectedRemoteProvider() -> RemoteAIProvider {
        guard let raw = settingsStore.string(forKey: selectedRemoteProviderKey),
              let provider = RemoteAIProvider(rawValue: raw) else {
            return .openRouter
        }
        return provider
    }

    func setSelectedRemoteProvider(_ provider: RemoteAIProvider) {
        settingsStore.set(provider.rawValue, forKey: selectedRemoteProviderKey)
    }
}
