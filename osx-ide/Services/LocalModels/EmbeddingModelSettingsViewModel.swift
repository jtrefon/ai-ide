import Foundation
import SwiftUI

@MainActor
final class EmbeddingModelSettingsViewModel: ObservableObject {
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

    @Published private(set) var models: [EmbeddingModelDefinition] = []

    /// Currently selected embedding model (for indexing)
    @Published var selectedModelId: String {
        didSet {
            persistSelectedModelId()
        }
    }

    @Published private(set) var status = Status(kind: .idle, message: "Select an embedding model for semantic search.")
    @Published private(set) var isDownloading = false
    @Published private(set) var progressFraction: Double = 0
    @Published private(set) var currentFileName: String? = nil

    private let downloader: EmbeddingModelDownloader
    private let settingsStore: SettingsStore

    private let selectedModelKey = "EmbeddingModel.SelectedId"

    init(
        downloader: EmbeddingModelDownloader = EmbeddingModelDownloader(),
        settingsStore: SettingsStore = SettingsStore(userDefaults: .standard)
    ) {
        self.downloader = downloader
        self.settingsStore = settingsStore
        self.models = EmbeddingModelCatalog.availableModels
        // Default to first bundled model if none selected
        let storedId = settingsStore.string(forKey: selectedModelKey) ?? ""
        if storedId.isEmpty && !EmbeddingModelCatalog.bundledModels.isEmpty {
            self.selectedModelId = EmbeddingModelCatalog.bundledModels[0].id
        } else {
            self.selectedModelId = storedId
        }
    }

    func refreshCatalog() {
        models = EmbeddingModelCatalog.availableModels
        if models.isEmpty {
            status = Status(kind: .warning, message: "No embedding models available.")
        }
    }
    
    /// Check if a model is bundled with the app (always available)
    func isBundled(_ model: EmbeddingModelDefinition) -> Bool {
        return EmbeddingModelCatalog.isBundled(modelId: model.id)
    }

    func isInstalled(_ model: EmbeddingModelDefinition) -> Bool {
        // Bundled models are always "installed"
        if isBundled(model) {
            return true
        }
        // Check if model file exists in the app support directory
        guard let url = try? LocalModelFileStore.modelsRootDirectory()
            .appendingPathComponent("embeddings", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.fileName)
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func selectModel(_ model: EmbeddingModelDefinition) {
        selectedModelId = model.id
        status = Status(kind: .success, message: "Selected \(model.name). Restart project to use new embedding model.")
    }

    func downloadModel(_ model: EmbeddingModelDefinition) async {
        // Bundled models don't need downloading
        guard !isBundled(model) else {
            status = Status(kind: .success, message: "\(model.name) is bundled with the app.")
            return
        }
        
        guard !isDownloading else { return }

        isDownloading = true
        progressFraction = 0
        currentFileName = nil
        status = Status(kind: .loading, message: "Downloading \(model.name)...")

        do {
            _ = try await downloader.download(model: model) { [weak self] progress in
                Task { @MainActor in
                    self?.progressFraction = progress.fractionCompleted
                    self?.currentFileName = progress.currentFileName
                }
            }

            status = Status(kind: .success, message: "Downloaded \(model.name).")
        } catch {
            status = Status(kind: .error, message: error.localizedDescription)
        }

        isDownloading = false
        currentFileName = nil
    }

    func deleteModel(_ model: EmbeddingModelDefinition) {
        // Bundled models cannot be deleted
        guard !isBundled(model) else {
            status = Status(kind: .warning, message: "Bundled models cannot be deleted.")
            return
        }
        
        do {
            let modelDir = try LocalModelFileStore.modelsRootDirectory()
                .appendingPathComponent("embeddings", isDirectory: true)
                .appendingPathComponent(model.id, isDirectory: true)

            if FileManager.default.fileExists(atPath: modelDir.path) {
                try FileManager.default.removeItem(at: modelDir)
            }

            if selectedModelId == model.id {
                selectedModelId = ""
            }
            status = Status(kind: .success, message: "Deleted \(model.name).")
        } catch {
            status = Status(kind: .error, message: error.localizedDescription)
        }
    }

    private func persistSelectedModelId() {
        settingsStore.set(selectedModelId, forKey: selectedModelKey)
    }
}
