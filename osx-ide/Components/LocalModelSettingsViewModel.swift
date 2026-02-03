import Foundation
import SwiftUI

@MainActor
final class LocalModelSettingsViewModel: ObservableObject {
    @Published var provider: AIProvider {
        didSet { providerStore.save(provider) }
    }

    @Published var localModelEnabled: Bool {
        didSet { persistLocalSettings() }
    }

    @Published var quantization: LocalModelQuantization {
        didSet { persistLocalSettings() }
    }

    @Published var allowRemoteFallback: Bool {
        didSet { persistLocalSettings() }
    }

    @Published var contextBudgetTokensDraft: Double

    @Published var maxAnswerTokensDraft: Double
    @Published var maxReasoningTokensDraft: Double

    @Published var temperatureDraft: Double

    @Published var selectedModelId: String {
        didSet {
            clampQuantizationToSelectedModelIfNeeded()
            clampContextBudgetToSelectedModelIfNeeded()
            persistLocalSettings()
        }
    }

    @Published private(set) var isDownloaded: Bool = false
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadErrorMessage: String? = nil
    @Published private(set) var modelSizeDisplayById: [String: String] = [:]

    private let providerStore: AIProviderSettingsStore
    private let localStore: LocalModelSettingsStore
    private let downloadService: LocalModelDownloadService
    private let metadataService: HuggingFaceModelMetadataService
    private let fileStore: LocalModelFileStore

    init(
        providerStore: AIProviderSettingsStore = AIProviderSettingsStore(),
        localStore: LocalModelSettingsStore = LocalModelSettingsStore(),
        downloadService: LocalModelDownloadService = LocalModelDownloadService(),
        metadataService: HuggingFaceModelMetadataService = HuggingFaceModelMetadataService(),
        fileStore: LocalModelFileStore = LocalModelFileStore()
    ) {
        self.providerStore = providerStore
        self.localStore = localStore
        self.downloadService = downloadService
        self.metadataService = metadataService
        self.fileStore = fileStore

        let provider = providerStore.load()
        let local = localStore.load()

        self.provider = provider
        self.localModelEnabled = local.isEnabled
        self.selectedModelId = local.selectedModelId
        self.quantization = local.quantization
        self.allowRemoteFallback = local.allowRemoteFallback
        self.contextBudgetTokensDraft = Double(local.contextBudgetTokens)
        self.maxAnswerTokensDraft = Double(local.maxAnswerTokens)
        self.maxReasoningTokensDraft = Double(local.maxReasoningTokens)
        self.temperatureDraft = local.temperature

        clampQuantizationToSelectedModelIfNeeded()
        clampContextBudgetToSelectedModelIfNeeded()
        clampMaxAnswerTokensIfNeeded()
        clampMaxReasoningTokensIfNeeded()
        clampTemperatureIfNeeded()

        Task { await refreshDownloadState() }
        Task { await loadModelSizes() }
    }

    private func persistLocalSettings() {
        clampQuantizationToSelectedModelIfNeeded()
        clampContextBudgetToSelectedModelIfNeeded()
        clampMaxAnswerTokensIfNeeded()
        clampMaxReasoningTokensIfNeeded()
        clampTemperatureIfNeeded()
        localStore.save(LocalModelSettings(
            isEnabled: localModelEnabled,
            selectedModelId: selectedModelId,
            quantization: quantization,
            allowRemoteFallback: allowRemoteFallback,
            contextBudgetTokens: Int(contextBudgetTokensDraft),
            maxAnswerTokens: Int(maxAnswerTokensDraft),
            maxReasoningTokens: Int(maxReasoningTokensDraft),
            temperature: temperatureDraft
        ))

        Task { await refreshDownloadState() }
    }

    func refreshDownloadState() async {
        isDownloaded = await downloadService.isDownloaded(
            modelId: selectedModelId,
            quantization: quantization
        )
    }

    func supportedQuantizationsForSelectedModel() -> [LocalModelQuantization] {
        LocalModelCatalog.item(id: selectedModelId)?.supportedQuantizations ?? LocalModelQuantization.allCases
    }

    func maxContextBudgetTokensForSelectedModel() -> Int {
        if let detected = detectContextLengthFromLocalConfig() {
            return detected
        }
        return LocalModelCatalog.item(id: selectedModelId)?.contextLength ?? 4096
    }

    private func detectContextLengthFromLocalConfig() -> Int? {
        let modelDirectory = fileStore.modelDirectory(modelId: selectedModelId, quantization: quantization)
        let configURL = modelDirectory.appendingPathComponent("config.json")

        guard let data = try? Data(contentsOf: configURL) else { return nil }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        let candidates: [String] = [
            "max_position_embeddings",
            "n_positions",
            "seq_length",
            "context_length",
            "model_max_length"
        ]

        for key in candidates {
            if let value = json[key] as? Int, value > 0 {
                return value
            }
            if let value = json[key] as? Double, value > 0 {
                return Int(value)
            }
            if let value = json[key] as? String, let intValue = Int(value), intValue > 0 {
                return intValue
            }
        }

        if let textConfig = json["text_config"] as? [String: Any] {
            for key in candidates {
                if let value = textConfig[key] as? Int, value > 0 {
                    return value
                }
                if let value = textConfig[key] as? Double, value > 0 {
                    return Int(value)
                }
                if let value = textConfig[key] as? String, let intValue = Int(value), intValue > 0 {
                    return intValue
                }
            }
        }

        return nil
    }

    func applyContextBudgetDraft() {
        clampContextBudgetToSelectedModelIfNeeded()
        persistLocalSettings()
    }

    func applyMaxAnswerTokensDraft() {
        clampMaxAnswerTokensIfNeeded()
        persistLocalSettings()
    }

    func applyMaxReasoningTokensDraft() {
        clampMaxReasoningTokensIfNeeded()
        persistLocalSettings()
    }

    func applyTemperatureDraft() {
        clampTemperatureIfNeeded()
        persistLocalSettings()
    }

    func modelSizeDisplayString(modelId: String) -> String? {
        modelSizeDisplayById[modelId]
    }

    func loadModelSizes() async {
        var updated: [String: String] = [:]
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file

        for item in LocalModelCatalog.items {
            do {
                let bytes = try await metadataService.fetchTotalSizeBytes(
                    repository: item.huggingFaceRepository,
                    files: item.files
                )

                if bytes > 0 {
                    updated[item.id] = formatter.string(fromByteCount: Int64(bytes))
                }
            } catch {
                continue
            }
        }

        modelSizeDisplayById = updated
    }

    private func clampQuantizationToSelectedModelIfNeeded() {
        let supported = supportedQuantizationsForSelectedModel()
        guard !supported.contains(quantization) else { return }
        if let first = supported.first {
            quantization = first
        }
    }

    private func clampContextBudgetToSelectedModelIfNeeded() {
        let maxTokens = maxContextBudgetTokensForSelectedModel()
        let minTokens = 512
        let clamped = min(Double(maxTokens), max(Double(minTokens), contextBudgetTokensDraft))
        contextBudgetTokensDraft = Double(Int(clamped))
    }

    private func clampMaxAnswerTokensIfNeeded() {
        let minTokens = 64
        let maxTokens = 2048
        let clamped = min(Double(maxTokens), max(Double(minTokens), maxAnswerTokensDraft))
        maxAnswerTokensDraft = Double(Int(clamped))
    }

    private func clampMaxReasoningTokensIfNeeded() {
        let minTokens = 64
        let maxTokens = 4096
        let clamped = min(Double(maxTokens), max(Double(minTokens), maxReasoningTokensDraft))
        maxReasoningTokensDraft = Double(Int(clamped))
    }

    private func clampTemperatureIfNeeded() {
        let minTemp = 0.0
        let maxTemp = 2.0
        temperatureDraft = min(maxTemp, max(minTemp, temperatureDraft))
    }

    func downloadSelectedModel() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        downloadErrorMessage = nil

        Task {
            do {
                try await downloadService.download(
                    modelId: selectedModelId,
                    quantization: quantization,
                    onProgress: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.downloadProgress = snapshot.fractionComplete
                        }
                    }
                )
                await refreshDownloadState()
            } catch {
                await refreshDownloadState()
                await MainActor.run {
                    self.downloadErrorMessage = error.localizedDescription
                }
            }

            isDownloading = false
        }
    }
}
