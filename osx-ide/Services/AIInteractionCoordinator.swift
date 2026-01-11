import Foundation

@MainActor
final class AIInteractionCoordinator {
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
        messages: [ChatMessage],
        explicitContext: String?,
        tools: [AITool],
        mode: AIMode,
        projectRoot: URL
    ) async -> Result<AIServiceResponse, AppError> {
        let maxAttempts = 3
        var lastError: AppError?

        for attempt in 1...maxAttempts {
            let augmentedContext = await ContextBuilder.buildContext(
                userInput: messages.last(where: { $0.role == .user })?.content ?? "",
                explicitContext: explicitContext,
                index: codebaseIndex,
                projectRoot: projectRoot
            )

            let result = await aiService.sendMessageResult(
                messages,
                context: augmentedContext,
                tools: tools,
                mode: mode,
                projectRoot: projectRoot
            )

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
