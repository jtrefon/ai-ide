import Foundation

@MainActor
final class AIInteractionCoordinator {
    struct SendMessageWithRetryRequest {
        let messages: [ChatMessage]
        let explicitContext: String?
        let tools: [AITool]
        let mode: AIMode
        let projectRoot: URL
        let runId: String?
        let stage: AIRequestStage?

        init(
            messages: [ChatMessage],
            explicitContext: String?,
            tools: [AITool],
            mode: AIMode,
            projectRoot: URL,
            runId: String? = nil,
            stage: AIRequestStage? = nil
        ) {
            self.messages = messages
            self.explicitContext = explicitContext
            self.tools = tools
            self.mode = mode
            self.projectRoot = projectRoot
            self.runId = runId
            self.stage = stage
        }
    }

    private var aiService: AIService
    private var codebaseIndex: CodebaseIndexProtocol?
    private let conversationPolicy: ConversationPolicyProtocol

    init(
        aiService: AIService,
        codebaseIndex: CodebaseIndexProtocol?,
        conversationPolicy: ConversationPolicyProtocol = ConversationPolicy()
    ) {
        self.aiService = aiService
        self.codebaseIndex = codebaseIndex
        self.conversationPolicy = conversationPolicy
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
#if DEBUG
        if request.mode == .chat {
            assert(request.tools.isEmpty, "Invariant violated: Chat mode request must not include tools")
        }

        if request.runId != nil {
            assert(request.stage != nil, "Invariant violated: runId is set but stage is nil")
        }
#endif
        let sanitizedMessages = sanitizeMessagesForModel(request.messages)
        let filteredTools = conversationPolicy.allowedTools(
            for: request.stage,
            mode: request.mode,
            from: request.tools
        )
        let maxAttempts = 3
        var lastError: AppError?

        for attempt in 1...maxAttempts {
            let userInput = request.messages.last(where: { $0.role == .user })?.content ?? ""
            let retriever: (any RAGRetriever)?
            if let codebaseIndex {
                retriever = CodebaseIndexRAGRetriever(index: codebaseIndex)
            } else {
                retriever = nil
            }

            let augmentedContext = await RAGContextBuilder.buildContext(
                userInput: userInput,
                explicitContext: request.explicitContext,
                retriever: retriever,
                projectRoot: request.projectRoot
            )

            let result = await aiService.sendMessageResult(AIServiceHistoryRequest(
                messages: sanitizedMessages,
                context: augmentedContext,
                tools: filteredTools,
                mode: request.mode,
                projectRoot: request.projectRoot,
                runId: request.runId,
                stage: request.stage
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

    private func sanitizeMessagesForModel(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.map { message in
            guard message.role == .assistant else { return message }
            guard message.reasoning?.isEmpty == false else { return message }

            return ChatMessage(
                role: message.role,
                content: message.content,
                context: ChatMessageContentContext(reasoning: nil, codeContext: message.codeContext),
                tool: ChatMessageToolContext(
                    toolName: message.toolName,
                    toolStatus: message.toolStatus,
                    target: ToolInvocationTarget(targetFile: message.targetFile, toolCallId: message.toolCallId),
                    toolCalls: message.toolCalls ?? []
                )
            )
        }
    }
}
