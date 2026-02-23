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
    private let settingsStore: any OpenRouterSettingsLoading
    private let eventBus: any EventBusProtocol

    init(
        aiService: AIService,
        codebaseIndex: CodebaseIndexProtocol?,
        conversationPolicy: ConversationPolicyProtocol = ConversationPolicy(),
        settingsStore: any OpenRouterSettingsLoading = OpenRouterSettingsStore(),
        eventBus: any EventBusProtocol
    ) {
        self.aiService = aiService
        self.codebaseIndex = codebaseIndex
        self.conversationPolicy = conversationPolicy
        self.settingsStore = settingsStore
        self.eventBus = eventBus
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
        let sanitizedMessages = sanitizeMessagesForModel(request.messages)
        let filteredTools = conversationPolicy.allowedTools(
            for: request.stage,
            mode: request.mode,
            from: request.tools
        )
        let maxAttempts = 7
        var lastError: AppError?
        let settings = settingsStore.load(includeApiKey: false)

        for attempt in 1...maxAttempts {
            let userInput = request.messages.last(where: { $0.role == .user })?.content ?? ""
            let retriever: (any RAGRetriever)?
            if let codebaseIndex,
                shouldUseRAGRetrieval(for: request.stage, settings: settings)
            {
                retriever = CodebaseIndexRAGRetriever(index: codebaseIndex)
            } else {
                retriever = nil
            }

            let augmentedContext = await RAGContextBuilder.buildContext(
                userInput: userInput,
                explicitContext: request.explicitContext,
                retriever: retriever,
                projectRoot: request.projectRoot,
                eventBus: eventBus
            )

            let historyRequest = AIServiceHistoryRequest(
                messages: sanitizedMessages,
                context: augmentedContext,
                tools: filteredTools,
                mode: request.mode,
                projectRoot: request.projectRoot,
                runId: request.runId,
                stage: request.stage
            )

            let isRateLimitError: (Error) -> Bool = { error in
                let errStr = String(describing: error).lowercased()
                return errStr.contains("429") || errStr.contains("rate-limit")
                    || errStr.contains("rate_limit")
            }

            let shouldUseStreaming = request.runId != nil && !isRunningUnitTests()

            // Use streaming in app runtime; disable in tests for deterministic harness telemetry
            if shouldUseStreaming, let runId = request.runId {
                do {
                    let response = try await aiService.sendMessageStreaming(
                        historyRequest, runId: runId)
                    return .success(response)
                } catch {
                    lastError = Self.mapToAppError(error, operation: "sendMessageStreaming")
                    if attempt < maxAttempts {
                        if isRateLimitError(error) {
                            let waitSeconds = min(
                                UInt64(pow(2.0, Double(attempt))) * 2_000_000_000, 60_000_000_000)
                            print(
                                "[AIInteractionCoordinator] Rate limit hit. Retrying attempt \(attempt+1)/\(maxAttempts) in \(waitSeconds / 1_000_000_000)s..."
                            )
                            try? await Task.sleep(nanoseconds: waitSeconds)
                        } else {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                    }
                }
            } else {
                let result = await aiService.sendMessageResult(historyRequest)

                switch result {
                case .success:
                    return result
                case .failure(let error):
                    lastError = error
                    if attempt < maxAttempts {
                        if isRateLimitError(error) {
                            let waitSeconds = min(
                                UInt64(pow(2.0, Double(attempt))) * 2_000_000_000, 60_000_000_000)
                            print(
                                "[AIInteractionCoordinator] Rate limit hit. Retrying attempt \(attempt+1)/\(maxAttempts) in \(waitSeconds / 1_000_000_000)s..."
                            )
                            try? await Task.sleep(nanoseconds: waitSeconds)
                        } else {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                    }
                }
            }
        }

        return .failure(lastError ?? .unknown("ConversationManager: sendMessageWithRetry failed"))
    }

    private static func mapToAppError(_ error: Error, operation: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .aiServiceError("AIService.\(operation) failed: \(error.localizedDescription)")
    }

    private func shouldUseRAGRetrieval(for stage: AIRequestStage?, settings: OpenRouterSettings)
        -> Bool
    {
        _ = stage
        _ = settings
        return true
    }

    private func sanitizeMessagesForModel(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.map { message in
            guard message.role == .assistant else { return message }
            guard message.reasoning?.isEmpty == false else { return message }

            return ChatMessage(
                role: message.role,
                content: message.content,
                context: ChatMessageContentContext(
                    reasoning: nil, codeContext: message.codeContext),
                tool: ChatMessageToolContext(
                    toolName: message.toolName,
                    toolStatus: message.toolStatus,
                    target: ToolInvocationTarget(
                        targetFile: message.targetFile, toolCallId: message.toolCallId),
                    toolCalls: message.toolCalls ?? []
                )
            )
        }
    }

    private func isRunningUnitTests() -> Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
