import Foundation

@MainActor
final class AIInteractionCoordinator {
    struct SendMessageWithRetryRequest {
        let messages: [ChatMessage]
        let explicitContext: String?
        let tools: [AITool]
        let mode: AIMode
        let projectRoot: URL
    }

    private var aiService: AIService
    private var codebaseIndex: CodebaseIndexProtocol?

    init(aiService: AIService, codebaseIndex: CodebaseIndexProtocol?) {
        self.aiService = aiService
        self.codebaseIndex = codebaseIndex
    }

    func updateAIService(_ newService: AIService) {
        aiService = newService
    }

    func updateCodebaseIndex(_ newIndex: CodebaseIndexProtocol?) {
        codebaseIndex = newIndex
    }

    func sendMessageWithRetry(
        _ request: SendMessageWithRetryRequest
    ) async -> Result<AIServiceResponse, AppError> {
        let maxAttempts = 3
        var lastError: AppError?

        for attempt in 1...maxAttempts {
            let augmentedContext = await ContextBuilder.buildContext(
                userInput: request.messages.last(where: { $0.role == .user })?.content ?? "",
                explicitContext: request.explicitContext,
                index: codebaseIndex,
                projectRoot: request.projectRoot
            )

            let result = await aiService.sendMessageResult(AIServiceHistoryRequest(
                messages: request.messages,
                context: augmentedContext,
                tools: request.tools,
                mode: request.mode,
                projectRoot: request.projectRoot
            ))

            switch result {
            case .success:
                return result
            case .failure(let error):
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        return .failure(lastError ?? .unknown("ConversationManager: sendMessageWithRetry failed"))
    }
}
