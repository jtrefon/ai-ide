import Foundation
import Combine
@preconcurrency import MLXLMCommon
import MLXLLM

actor LocalModelProcessAIService: AIService {
    struct NoOpEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {}

        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            AnyCancellable {}
        }
    }

    protocol ModelFileStoring: Sendable {
        func isModelInstalled(_ model: LocalModelDefinition) -> Bool
        func modelDirectory(modelId: String) throws -> URL
    }

    struct LocalModelFileStoreAdapter: ModelFileStoring {
        func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
            LocalModelFileStore.isModelInstalled(model)
        }

        func modelDirectory(modelId: String) throws -> URL {
            try LocalModelFileStore.modelDirectory(modelId: modelId)
        }
    }

    protocol LocalModelGenerating: Sendable {
        func generate(modelDirectory: URL, prompt: String, runId: String?) async throws -> String
    }

    actor NativeMLXGenerator: LocalModelGenerating {
        private let eventBus: EventBusProtocol
        private var containersByModelDirectory: [URL: ModelContainer] = [:]

        init(eventBus: EventBusProtocol) {
            self.eventBus = eventBus
        }

        func generate(modelDirectory: URL, prompt: String, runId: String?) async throws -> String {
            let container = try await loadContainerCached(modelDirectory: modelDirectory)
            let chat: [Chat.Message] = [.user(prompt)]
            let userInput = UserInput(chat: chat)
            let parameters = GenerateParameters(
                maxTokens: 512,
                temperature: 0.2,
                topP: 1.0
            )
            let eventBus = self.eventBus

            return try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)
                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: context
                )

                var output = ""
                for await generation in stream {
                    switch generation {
                    case .chunk(let text):
                        output.append(text)
                        if let runId, !text.isEmpty {
                            await MainActor.run {
                                eventBus.publish(LocalModelStreamingChunkEvent(runId: runId, chunk: text))
                            }
                        }
                    case .info:
                        break
                    case .toolCall:
                        break
                    }
                }
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        private func loadContainerCached(modelDirectory: URL) async throws -> ModelContainer {
            let cacheKey = modelDirectory.resolvingSymlinksInPath().standardizedFileURL
            if let existing = containersByModelDirectory[cacheKey] {
                return existing
            }
            let container = try await MLXLMCommon.loadModelContainer(directory: cacheKey)
            containersByModelDirectory[cacheKey] = container
            return container
        }
    }

    private let selectionStore: LocalModelSelectionStore
    private let fileStore: ModelFileStoring
    private let generator: LocalModelGenerating

    init(
        selectionStore: LocalModelSelectionStore = LocalModelSelectionStore(),
        fileStore: ModelFileStoring = LocalModelFileStoreAdapter(),
        generator: LocalModelGenerating? = nil,
        eventBus: EventBusProtocol? = nil
    ) {
        self.selectionStore = selectionStore
        self.fileStore = fileStore
        let resolvedEventBus = eventBus ?? NoOpEventBus()
        self.generator = generator ?? NativeMLXGenerator(eventBus: resolvedEventBus)
    }

    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
        try await sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: request.message)],
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot
        ))
    }

    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
        let modelId = selectionStore.selectedModelId()
        guard !modelId.isEmpty else {
            throw AppError.aiServiceError("No local model selected.")
        }
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw AppError.aiServiceError("Selected local model is not recognized: \(modelId)")
        }
        guard fileStore.isModelInstalled(model) else {
            throw AppError.aiServiceError("Local model is not downloaded: \(model.displayName)")
        }

        let modelDirectory = try fileStore.modelDirectory(modelId: model.id)
        let prompt = buildPrompt(messages: request.messages, explicitContext: request.context)
        let output = try await generator.generate(modelDirectory: modelDirectory, prompt: prompt, runId: request.runId)
        return AIServiceResponse(content: output, toolCalls: nil)
    }

    func explainCode(_ code: String) async throws -> String {
        let prompt = "Explain the following code in clear, concise terms:\n\n\(code)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: prompt,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let prompt = "Refactor this code using the following instructions:\n\(instructions)\n\nCode:\n\(code)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: prompt,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func generateCode(_ prompt: String) async throws -> String {
        let message = "Generate code for the following request:\n\(prompt)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: message,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        let prompt = "Fix this code. Error message:\n\(error)\n\nCode:\n\(code)"
        let response = try await sendMessage(AIServiceMessageWithProjectRootRequest(
            message: prompt,
            context: nil,
            tools: nil,
            mode: nil,
            projectRoot: nil
        ))
        return response.content ?? ""
    }

    private func buildPrompt(messages: [ChatMessage], explicitContext: String?) -> String {
        var sections: [String] = []
        if let explicitContext, !explicitContext.isEmpty {
            sections.append("Context:\n\(explicitContext)\n")
        }

        let transcript = messages.map { message in
            let role: String
            switch message.role {
            case .user:
                role = "User"
            case .assistant:
                role = "Assistant"
            case .system:
                role = "System"
            case .tool:
                role = "Tool"
            }
            return "\(role): \(message.content)"
        }.joined(separator: "\n")
        sections.append(transcript)
        sections.append("Assistant:")
        return sections.joined(separator: "\n")
    }
}
