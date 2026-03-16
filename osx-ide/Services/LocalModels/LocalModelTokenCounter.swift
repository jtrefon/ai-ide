import Foundation
import Hub
import Tokenizers

actor LocalModelTokenCounter {
    static let shared = LocalModelTokenCounter()

    private var tokenizersByModelId: [String: any Tokenizer] = [:]

    func tokenCount(text: String, modelId: String) async throws -> Int {
        let tokenizer = try await tokenizer(for: modelId)
        return tokenizer.encode(text: text).count
    }

    private func tokenizer(for modelId: String) async throws -> any Tokenizer {
        if let cached = tokenizersByModelId[modelId] {
            return cached
        }

        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw AppError.aiServiceError("Selected local model is not recognized: \(modelId)")
        }

        let modelDirectory = try LocalModelFileStore.runtimeModelDirectory(for: model)
        let tokenizer = try await AutoTokenizer.from(
            modelFolder: modelDirectory,
            hubApi: HubApi(useOfflineMode: true)
        )
        tokenizersByModelId[modelId] = tokenizer
        return tokenizer
    }
}
