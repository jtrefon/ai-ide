import Foundation

@MainActor
final class LocalInteractionService {
    private let aiService: AIService
    private let eventBus: EventBusProtocol

    init(
        aiService: AIService,
        eventBus: EventBusProtocol
    ) {
        self.aiService = aiService
        self.eventBus = eventBus
    }

    struct InteractionRequest {
        let messages: [ChatMessage]
        let explicitContext: String?
        let projectRoot: URL
        let runId: String?
        let conversationId: String?

        init(
            messages: [ChatMessage],
            explicitContext: String? = nil,
            projectRoot: URL,
            runId: String? = nil,
            conversationId: String? = nil
        ) {
            self.messages = messages
            self.explicitContext = explicitContext
            self.projectRoot = projectRoot
            self.runId = runId
            self.conversationId = conversationId
        }
    }

    func sendMessage(_ request: InteractionRequest) async -> Result<AIServiceResponse, AppError> {
        let historyRequest = AIServiceHistoryRequest(
            messages: request.messages,
            mediaAttachments: [],
            context: request.explicitContext,
            tools: [],
            mode: .chat,
            projectRoot: request.projectRoot,
            runId: request.runId,
            stage: nil,
            conversationId: request.conversationId
        )

        if let runId = request.runId {
            do {
                let response = try await aiService.sendMessageStreaming(historyRequest, runId: runId)
                return .success(response)
            } catch {
                return .failure(.aiServiceError(error.localizedDescription))
            }
        }

        return await aiService.sendMessageResult(historyRequest)
    }
}
