import Foundation
import SwiftUI

@MainActor
final class LocalModelSettingsViewModel: ObservableObject {
    struct Status: Equatable {
        enum Kind {
            case idle
            case loading
            case success
            case warning
            case error
        }

        let kind: Kind
        let message: String
    }

    @Published private(set) var models: [LocalModelDefinition] = []

    @Published var offlineModeEnabled: Bool {
        didSet {
            persistOfflineModeEnabled()
        }
    }

    @Published var selectedModelId: String {
        didSet {
            persistSelectedModelId()
        }
    }

    @Published private(set) var status = Status(kind: .idle, message: "Local models not configured.")
    @Published private(set) var isDownloading = false
    @Published private(set) var progressFraction: Double = 0
    @Published private(set) var currentFileName: String? = nil

    private let downloader: LocalModelDownloader
    private let settingsStore: SettingsStore

    private let selectedModelKey = "LocalModel.SelectedId"
    private let offlineModeEnabledKey = "AI.OfflineModeEnabled"

    init(
        downloader: LocalModelDownloader = LocalModelDownloader(),
        settingsStore: SettingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)
    ) {
        self.downloader = downloader
        self.settingsStore = settingsStore
        self.models = LocalModelCatalog.allModels()
        self.selectedModelId = settingsStore.string(forKey: selectedModelKey) ?? ""
        self.offlineModeEnabled = settingsStore.bool(forKey: offlineModeEnabledKey, default: false)
    }

    func refreshCatalog() {
        models = LocalModelCatalog.allModels()
        if models.isEmpty {
            status = Status(kind: .warning, message: "No local models available (catalog returned 0 entries).")
        }
    }

    func isInstalled(_ model: LocalModelDefinition) -> Bool {
        LocalModelFileStore.isModelInstalled(model)
    }

    func selectModel(_ model: LocalModelDefinition) {
        selectedModelId = model.id
        status = Status(kind: .success, message: "Selected \(model.displayName).")
    }

    func downloadModel(_ model: LocalModelDefinition) async {
        guard !isDownloading else { return }

        isDownloading = true
        progressFraction = 0
        currentFileName = nil
        status = Status(kind: .loading, message: "Downloading \(model.displayName)...")

        do {
            try await downloader.download(model: model) { [weak self] progress in
                Task { @MainActor in
                    self?.progressFraction = progress.fractionCompleted
                    self?.currentFileName = progress.currentFileName
                }
            }

            status = Status(kind: .success, message: "Downloaded \(model.displayName).")
        } catch {
            status = Status(kind: .error, message: error.localizedDescription)
        }

        isDownloading = false
        currentFileName = nil
    }

    func deleteModel(_ model: LocalModelDefinition) {
        do {
            try LocalModelFileStore.deleteModelDirectory(modelId: model.id)
            if selectedModelId == model.id {
                selectedModelId = ""
            }
            status = Status(kind: .success, message: "Deleted \(model.displayName).")
        } catch {
            status = Status(kind: .error, message: error.localizedDescription)
        }
    }

    private func persistSelectedModelId() {
        settingsStore.set(selectedModelId, forKey: selectedModelKey)
    }

    private func persistOfflineModeEnabled() {
        settingsStore.set(offlineModeEnabled, forKey: offlineModeEnabledKey)
        if offlineModeEnabled {
            status = Status(kind: .success, message: "Offline Mode enabled. OpenRouter is disabled.")
        }
    }
}
