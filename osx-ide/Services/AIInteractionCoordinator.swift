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
        let conversationId: String?

        init(
            messages: [ChatMessage],
            explicitContext: String?,
            tools: [AITool],
            mode: AIMode,
            projectRoot: URL,
            runId: String? = nil,
            stage: AIRequestStage? = nil,
            conversationId: String? = nil
        ) {
            self.messages = messages
            self.explicitContext = explicitContext
            self.tools = tools
            self.mode = mode
            self.projectRoot = projectRoot
            self.runId = runId
            self.stage = stage
            self.conversationId = conversationId
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
        let isUnitTestRun = isRunningUnitTests()
        let sanitizedMessages = sanitizeMessagesForModel(request.messages)
        let filteredTools = conversationPolicy.allowedTools(
            for: request.stage,
            mode: request.mode,
            from: request.tools
        )
        let maxAttempts = maxAttemptsForRequestStage(
            request.stage,
            isRunningUnitTests: isUnitTestRun
        )
        var lastError: AppError?
        let settings = settingsStore.load(includeApiKey: false)
        let userInput = request.messages.last(where: { $0.role == .user })?.content ?? ""
        let retriever: (any RAGRetriever)?
        if let codebaseIndex, shouldUseRAGRetrieval(for: request.stage, settings: settings) {
            retriever = CodebaseIndexRAGRetriever(index: codebaseIndex)
        } else {
            retriever = nil
        }
        let augmentedContext = await RAGContextBuilder.buildContext(
            userInput: userInput,
            explicitContext: request.explicitContext,
            retriever: retriever,
            projectRoot: request.projectRoot,
            stage: request.stage,
            conversationId: request.conversationId,
            eventBus: eventBus
        )

        for attempt in 1...maxAttempts {
            if Task.isCancelled {
                return .failure(.aiServiceError("Request cancelled"))
            }

            let retryMessages: [ChatMessage]
            if attempt > 1 {
                let retryReason = lastError?.localizedDescription ?? "previous attempt failed"
                let retryPromptTemplate: String
                do {
                    retryPromptTemplate = try PromptRepository.shared.prompt(
                        key: "ConversationFlow/Corrections/retry_context_message",
                        projectRoot: request.projectRoot
                    )
                } catch {
                    return .failure(Self.mapToAppError(error, operation: "prompt.retry_context_message"))
                }
                let retryContextMessage = ChatMessage(
                    role: .system,
                    content: retryPromptTemplate
                        .replacingOccurrences(of: "{{attempt}}", with: String(attempt))
                        .replacingOccurrences(of: "{{max_attempts}}", with: String(maxAttempts))
                        .replacingOccurrences(of: "{{retry_reason}}", with: retryReason)
                )
                retryMessages = sanitizedMessages + [retryContextMessage]
            } else {
                retryMessages = sanitizedMessages
            }

            let historyRequest = AIServiceHistoryRequest(
                messages: retryMessages,
                context: augmentedContext,
                tools: filteredTools,
                mode: request.mode,
                projectRoot: request.projectRoot,
                runId: request.runId,
                stage: request.stage,
                conversationId: request.conversationId
            )

            let isRateLimitError: (Error) -> Bool = { error in
                let errStr = String(describing: error).lowercased()
                return errStr.contains("429") || errStr.contains("rate-limit")
                    || errStr.contains("rate_limit")
            }

            let shouldUseStreaming = shouldUseStreamingForRequest(
                runId: request.runId,
                stage: request.stage,
                isRunningUnitTests: isUnitTestRun
            )

            // Use streaming in app runtime; disable in tests for deterministic harness telemetry
            if shouldUseStreaming, let runId = request.runId {
                do {
                    let response = try await aiService.sendMessageStreaming(
                        historyRequest, runId: runId)
                    return .success(response)
                } catch {
                    if isCancellationError(error) || Task.isCancelled {
                        return .failure(.aiServiceError("Request cancelled"))
                    }
                    lastError = Self.mapToAppError(error, operation: "sendMessageStreaming")
                    if attempt < maxAttempts {
                        if isRateLimitError(error) {
                            let waitSeconds = retryDelayNanoseconds(
                                forAttempt: attempt,
                                stage: request.stage,
                                isRateLimitError: true,
                                isRunningUnitTests: isUnitTestRun
                            )
                            print(
                                "[AIInteractionCoordinator] Rate limit hit. Retrying attempt \(attempt+1)/\(maxAttempts) in \(waitSeconds / 1_000_000_000)s..."
                            )
                            guard await sleepRespectingCancellation(nanoseconds: waitSeconds) else {
                                return .failure(.aiServiceError("Request cancelled"))
                            }
                        } else {
                            let waitSeconds = retryDelayNanoseconds(
                                forAttempt: attempt,
                                stage: request.stage,
                                isRateLimitError: false,
                                isRunningUnitTests: isUnitTestRun
                            )
                            guard await sleepRespectingCancellation(nanoseconds: waitSeconds) else {
                                return .failure(.aiServiceError("Request cancelled"))
                            }
                        }
                    }
                }
            } else {
                let result = await aiService.sendMessageResult(historyRequest)

                switch result {
                case .success:
                    return result
                case .failure(let error):
                    if isCancellationError(error) || Task.isCancelled {
                        return .failure(.aiServiceError("Request cancelled"))
                    }
                    lastError = error
                    if attempt < maxAttempts {
                        if isRateLimitError(error) {
                            let waitSeconds = retryDelayNanoseconds(
                                forAttempt: attempt,
                                stage: request.stage,
                                isRateLimitError: true,
                                isRunningUnitTests: isUnitTestRun
                            )
                            print(
                                "[AIInteractionCoordinator] Rate limit hit. Retrying attempt \(attempt+1)/\(maxAttempts) in \(waitSeconds / 1_000_000_000)s..."
                            )
                            guard await sleepRespectingCancellation(nanoseconds: waitSeconds) else {
                                return .failure(.aiServiceError("Request cancelled"))
                            }
                        } else {
                            let waitSeconds = retryDelayNanoseconds(
                                forAttempt: attempt,
                                stage: request.stage,
                                isRateLimitError: false,
                                isRunningUnitTests: isUnitTestRun
                            )
                            guard await sleepRespectingCancellation(nanoseconds: waitSeconds) else {
                                return .failure(.aiServiceError("Request cancelled"))
                            }
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

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let appError = error as? AppError {
            let normalized = appError.localizedDescription.lowercased()
            return normalized.contains("cancellationerror")
                || normalized.contains("request cancelled")
                || normalized.contains("request canceled")
                || normalized.contains("cancelled")
                || normalized.contains("canceled")
        }
        let normalized = String(describing: error).lowercased()
        return normalized.contains("cancellationerror")
            || normalized.contains("request cancelled")
            || normalized.contains("request canceled")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
    }

    private func sleepRespectingCancellation(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    func maxAttemptsForRequestStage(
        _ stage: AIRequestStage?,
        isRunningUnitTests: Bool = false
    ) -> Int {
        if isRunningUnitTests {
            switch stage {
            case .final_response:
                return 2
            case .tool_loop:
                return 3
            default:
                return 3
            }
        }

        switch stage {
        case .final_response:
            return 3
        case .tool_loop:
            return 5
        default:
            return 7
        }
    }

    func retryDelayNanoseconds(
        forAttempt attempt: Int,
        stage: AIRequestStage?,
        isRateLimitError: Bool,
        isRunningUnitTests: Bool = false
    ) -> UInt64 {
        guard isRateLimitError else {
            if isRunningUnitTests {
                return 1_000_000_000
            }
            return 2_000_000_000
        }

        let baseDelay = UInt64(pow(2.0, Double(attempt))) * 2_000_000_000
        let maxDelay: UInt64
        switch stage {
        case .final_response:
            maxDelay = 8_000_000_000
        case .tool_loop:
            maxDelay = 16_000_000_000
        default:
            maxDelay = 60_000_000_000
        }

        if isRunningUnitTests {
            return min(baseDelay, min(maxDelay, 4_000_000_000))
        }

        return min(baseDelay, maxDelay)
    }

    private func shouldUseRAGRetrieval(
        for stage: AIRequestStage?,
        settings: OpenRouterSettings
    ) -> Bool {
        guard stage != .tool_loop else {
            return settings.ragEnabledDuringToolLoop
        }
        return true
    }

    func shouldUseStreamingForRequest(
        runId: String?,
        stage: AIRequestStage?,
        isRunningUnitTests: Bool
    ) -> Bool {
        runId != nil
            && !isRunningUnitTests
            && stage != .final_response
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
