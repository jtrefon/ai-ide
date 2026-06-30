import Foundation
import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
import Tokenizers

actor FIMInferenceService {
    private var modelContainer: ModelContainer?
    nonisolated let modelId: String
    private let modelDirectory: URL
    private var generationTask: Task<Void, Never>?

    init(modelId: String) async throws {
        self.modelId = modelId
        guard !modelId.isEmpty else {
            throw AppError.aiServiceError("No local model selected for completions.")
        }
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw AppError.aiServiceError("Selected completion model is not recognized: \(modelId)")
        }
        guard LocalModelFileStore.isModelInstalled(model) else {
            throw AppError.aiServiceError("Completion model is not downloaded: \(model.displayName)")
        }
        self.modelDirectory = try LocalModelFileStore.runtimeModelDirectory(for: model)
    }

    private struct FIMTokenizerLoader: TokenizerLoader {
        let modelDirectory: URL
        func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
            let upstream = try await AutoTokenizer.from(modelFolder: modelDirectory)
            return FIMTokenBridge(upstream: upstream)
        }
    }

    private final class FIMTokenBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
        let upstream: any Tokenizers.Tokenizer
        init(upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }
        func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
        func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
        func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }
        func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
            let combined = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
            return encode(text: combined, addSpecialTokens: false)
        }
    }

    private func ensureLoaded() async throws -> ModelContainer {
        if let container = modelContainer { return container }
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: FIMTokenizerLoader(modelDirectory: modelDirectory)
        )
        modelContainer = container
        return container
    }

    func unload() {
        generationTask?.cancel()
        generationTask = nil
        modelContainer = nil
        Memory.clearCache()
    }

    func generate(prefix: String, suffix: String, maxTokens: Int = 64) async throws -> String {
        var output = ""
        for try await chunk in generateStream(prefix: prefix, suffix: suffix, maxTokens: maxTokens) {
            output.append(chunk)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateStream(
        prefix: String,
        suffix: String,
        maxTokens: Int = 64
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { [self] continuation in
            let task = Task {
                do {
                    let container = try await ensureLoaded()
                    guard let model = LocalModelCatalog.model(id: modelId) else {
                        continuation.finish(throwing: AppError.aiServiceError("Completion model not found: \(modelId)"))
                        return
                    }
                    let fimTokens = model.fimTokens

                    let prompt: String
                    if let fimTokens {
                        prompt = "\(fimTokens.prefix)\(prefix)\(fimTokens.suffix)\(suffix)\(fimTokens.middle)"
                    } else {
                        prompt = prefix
                    }

                    let contextLength = model.supportsFIM ? 4096 : 2048
                    let parameters = GenerateParameters(
                        maxTokens: min(maxTokens, 512),
                        maxKVSize: contextLength,
                        kvBits: 4,
                        temperature: 0.1,
                        topP: 0.9,
                        repetitionPenalty: nil,
                        repetitionContextSize: 20,
                        prefillStepSize: 512
                    )

                    let tokenizer = await container.tokenizer
                    let tokenIds = tokenizer.encode(text: prompt, addSpecialTokens: true)
                    let input = LMInput(text: LMInput.Text(tokens: MLXArray(tokenIds)))

                    let stream = try await container.generate(input: input, parameters: parameters)
                    for await generation in stream {
                        if Task.isCancelled { break }
                        if case .chunk(let text) = generation, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            generationTask = Task {
                await task.value
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.generationTask?.cancel()
                }
            }
        }
    }
}