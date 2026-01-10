//
//  ConversationManager.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Combine
import SwiftUI

@MainActor
final class ConversationManager: ObservableObject, ConversationManagerProtocol {
    @Published var currentInput: String = ""
    @Published var isSending: Bool = false
    @Published var error: String? = nil
    @Published var currentMode: AIMode = .chat
    @Published var cancelledToolCallIds: Set<String> = []

    private let useMultiRoleAgentOrchestrator: Bool = false

    private var conversationId: String
    private var hasStartedConversation: Bool = false

    private let historyManager: ChatHistoryManager
    private let toolExecutor: AIToolExecutor
    private var aiService: AIService
    private let errorManager: ErrorManagerProtocol
    private let fileSystemService: FileSystemService
    private let workspaceService: WorkspaceServiceProtocol
    private let eventBus: EventBusProtocol
    private var codebaseIndex: CodebaseIndexProtocol?
    private var projectRoot: URL
    private var cancellables = Set<AnyCancellable>()

    private func conversationIdFileURL(projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("conversation_id.txt")
    }

    private func loadPersistedConversationId(projectRoot: URL) -> String? {
        let url = conversationIdFileURL(projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func persistConversationId(projectRoot: URL, conversationId: String) {
        let url = conversationIdFileURL(projectRoot: projectRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? conversationId.write(to: url, atomically: true, encoding: .utf8)
    }

    var messages: [ChatMessage] {
        historyManager.messages
    }

    var currentConversationId: String {
        conversationId
    }

    private var pathValidator: PathValidator {
        workspaceService.makePathValidator(projectRoot: projectRoot)
    }

    private var allTools: [AITool] {
        let validator = pathValidator
        var tools: [AITool] = []

        if let codebaseIndex {
            tools.append(IndexFindFilesTool(index: codebaseIndex))
            tools.append(IndexListFilesTool(index: codebaseIndex))
            tools.append(IndexSearchTextTool(index: codebaseIndex))
            tools.append(IndexReadFileTool(index: codebaseIndex))
            tools.append(IndexSearchSymbolsTool(index: codebaseIndex))
        }

        tools.append(
            WriteFileTool(
                fileSystemService: fileSystemService, pathValidator: validator, eventBus: eventBus))
        tools.append(
            WriteFilesTool(
                fileSystemService: fileSystemService, pathValidator: validator, eventBus: eventBus))
        tools.append(CreateFileTool(pathValidator: validator, eventBus: eventBus))
        tools.append(DeleteFileTool(pathValidator: validator, eventBus: eventBus))
        tools.append(
            ReplaceInFileTool(
                fileSystemService: fileSystemService, pathValidator: validator, eventBus: eventBus))
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: validator))

        tools.append(
            ArchitectAdvisorTool(
                aiService: aiService, index: codebaseIndex, projectRoot: projectRoot))
        tools.append(PlannerTool())

        tools.append(PatchSetListTool())
        tools.append(PatchSetApplyTool(eventBus: eventBus, projectRoot: projectRoot))
        tools.append(PatchSetClearTool())

        tools.append(CheckpointListTool())
        tools.append(CheckpointRestoreTool(eventBus: eventBus, projectRoot: projectRoot))

        tools.append(ConversationFoldTool(projectRoot: projectRoot))

        return tools
    }

    private var availableTools: [AITool] {
        return currentMode.allowedTools(from: allTools)
    }

    init(
        aiService: AIService,
        errorManager: ErrorManagerProtocol,
        fileSystemService: FileSystemService = FileSystemService(),
        workspaceService: WorkspaceServiceProtocol,
        eventBus: EventBusProtocol,
        projectRoot: URL? = nil,
        codebaseIndex: CodebaseIndexProtocol? = nil
    ) {
        self.conversationId = UUID().uuidString
        self.aiService = aiService
        self.errorManager = errorManager
        self.fileSystemService = fileSystemService
        self.workspaceService = workspaceService
        self.eventBus = eventBus
        let root = projectRoot ?? FileManager.default.temporaryDirectory
        self.projectRoot = root
        self.codebaseIndex = codebaseIndex

        self.historyManager = ChatHistoryManager()
        self.historyManager.setProjectRoot(root)
        self.toolExecutor = AIToolExecutor(
            fileSystemService: fileSystemService, errorManager: errorManager, projectRoot: root)

        Task.detached(priority: .utility) {
            await AppLogger.shared.setProjectRoot(root)
            await ConversationLogStore.shared.setProjectRoot(root)
            await ExecutionLogStore.shared.setProjectRoot(root)
            await ConversationIndexStore.shared.setProjectRoot(root)
            await ConversationPlanStore.shared.setProjectRoot(root)
            await PatchSetStore.shared.setProjectRoot(root)
            await CheckpointManager.shared.setProjectRoot(root)
        }

        setupObservation()

        Task.detached(priority: .utility) {
            let logPath = await AIToolTraceLogger.shared.currentLogFilePath()
            await AIToolTraceLogger.shared.log(
                type: "trace.start",
                data: [
                    "logFile": logPath,
                    "mode": await self.currentMode.rawValue,
                    "projectRoot": await self.projectRoot.path,
                ])
        }
    }

    private func setupObservation() {
        historyManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func updateAIService(_ newService: AIService) {
        self.aiService = newService
    }

    func updateCodebaseIndex(_ newIndex: CodebaseIndexProtocol?) {
        self.codebaseIndex = newIndex
    }

    func updateProjectRoot(_ newRoot: URL) {
        if projectRoot.standardizedFileURL == newRoot.standardizedFileURL {
            return
        }

        projectRoot = newRoot

        if let persisted = loadPersistedConversationId(projectRoot: newRoot) {
            conversationId = persisted
            hasStartedConversation = true
        } else {
            persistConversationId(projectRoot: newRoot, conversationId: conversationId)
        }

        historyManager.setProjectRoot(newRoot)

        let newRootPath = newRoot.path
        let initialMode = self.currentMode.rawValue
        let initialConversationId = self.conversationId

        let shouldStartConversation = !hasStartedConversation
        if shouldStartConversation {
            hasStartedConversation = true
        }

        Task.detached(priority: .utility) {
            await AppLogger.shared.setProjectRoot(newRoot)
            await ConversationLogStore.shared.setProjectRoot(newRoot)
            await ExecutionLogStore.shared.setProjectRoot(newRoot)
            await ConversationIndexStore.shared.setProjectRoot(newRoot)
            await ConversationPlanStore.shared.setProjectRoot(newRoot)
            await PatchSetStore.shared.setProjectRoot(newRoot)
            await CheckpointManager.shared.setProjectRoot(newRoot)
            await AppLogger.shared.info(
                category: .app, message: "logging.project_root_set",
                metadata: [
                    "projectRoot": newRootPath
                ])

            if shouldStartConversation {
                await AppLogger.shared.info(
                    category: .conversation, message: "conversation.start",
                    metadata: [
                        "conversationId": initialConversationId,
                        "mode": initialMode,
                        "projectRoot": newRootPath,
                    ])
                await ConversationLogStore.shared.append(
                    conversationId: initialConversationId,
                    type: "conversation.start",
                    data: [
                        "mode": initialMode,
                        "projectRoot": newRootPath,
                    ]
                )

                await ConversationIndexStore.shared.appendStart(
                    conversationId: initialConversationId,
                    mode: initialMode,
                    projectRootPath: newRootPath
                )
            }
        }
    }

    func sendMessage() {
        sendMessage(context: nil)
    }

    func sendMessage(context: String? = nil) {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessageText = currentInput
        let modeRawValue = currentMode.rawValue
        let projectRootPath = projectRoot.path
        let hasSelectionContext = (context?.isEmpty == false)
        let conversationId = self.conversationId

        Task.detached(priority: .utility) {
            await AIToolTraceLogger.shared.log(
                type: "chat.user_message",
                data: [
                    "mode": modeRawValue,
                    "projectRoot": projectRootPath,
                    "inputLength": userMessageText.count,
                    "hasSelectionContext": hasSelectionContext,
                ])

            await AppLogger.shared.info(
                category: .conversation, message: "chat.user_message",
                metadata: [
                    "conversationId": conversationId,
                    "mode": modeRawValue,
                    "projectRoot": projectRootPath,
                    "inputLength": userMessageText.count,
                    "hasSelectionContext": hasSelectionContext,
                ])
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.user_message",
                data: [
                    "content": userMessageText,
                    "hasSelectionContext": hasSelectionContext,
                ]
            )
        }

        let userMessage = ChatMessage(
            role: .user,
            content: currentInput,
            context: ChatMessageContentContext(codeContext: context)
        )
        historyManager.append(userMessage)

        currentInput = ""
        isSending = true
        error = nil

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let thresholds = ConversationFoldingThresholds()
                if let foldResult = try await ConversationFoldingService.fold(
                    messages: self.messages,
                    projectRoot: self.projectRoot,
                    thresholds: thresholds
                ) {
                    self.historyManager.removeOldestMessages(count: foldResult.foldedMessageCount)

                    await AIToolTraceLogger.shared.log(type: "chat.context_folded", data: [
                        "foldId": foldResult.entry.id,
                        "foldedMessageCount": foldResult.foldedMessageCount,
                        "summary": foldResult.entry.summary,
                    ])
                }

                let modeRawValue = self.currentMode.rawValue
                let projectRootPath = self.projectRoot.path
                let conversationId = self.conversationId
                let historyCount = self.messages.count

                Task.detached(priority: .utility) {
                    await AIToolTraceLogger.shared.log(
                        type: "chat.ai_request_start",
                        data: [
                            "mode": modeRawValue,
                            "projectRoot": projectRootPath,
                            "historyCount": historyCount,
                        ])

                    await AppLogger.shared.info(
                        category: .ai, message: "chat.ai_request_start",
                        metadata: [
                            "conversationId": conversationId,
                            "mode": modeRawValue,
                            "projectRoot": projectRootPath,
                            "historyCount": historyCount,
                        ])
                    await ConversationLogStore.shared.append(
                        conversationId: conversationId,
                        type: "chat.ai_request_start",
                        data: [
                            "mode": modeRawValue,
                            "historyCount": historyCount,
                        ]
                    )
                }

                var currentResponse = try await sendMessageWithRetry(
                    messages: self.messages,
                    context: context,
                    tools: availableTools,
                    mode: currentMode,
                    projectRoot: projectRoot
                )
                .get()

                if currentMode == .agent, useMultiRoleAgentOrchestrator {
                    let orchestrator = AgentOrchestrator()
                    let env = AgentOrchestrator.Environment(
                        allTools: availableTools,
                        send: { [self] request in
                            let augmentedContext = await ContextBuilder.buildContext(
                                userInput: request.messages.last(where: { $0.role == .user })?
                                    .content ?? "",
                                explicitContext: context,
                                index: self.codebaseIndex,
                                projectRoot: self.projectRoot
                            )
                            return try await self.aiService.sendMessage(
                                request.messages, context: augmentedContext, tools: request.tools,
                                mode: self.currentMode, projectRoot: self.projectRoot)
                        },
                        executeTools: { request in
                            await self.toolExecutor.executeBatch(
                                request.toolCalls, availableTools: request.tools,
                                conversationId: self.conversationId
                            ) { progressMsg in
                                if progressMsg.isToolExecution {
                                    self.historyManager.upsertToolExecutionMessage(progressMsg)
                                } else {
                                    self.historyManager.append(progressMsg)
                                }
                            }
                        },
                        onMessage: { msg in
                            if msg.isToolExecution {
                                self.historyManager.upsertToolExecutionMessage(msg)
                            } else {
                                self.historyManager.append(msg)
                            }
                        }
                    )
                    let result = try await orchestrator.run(
                        initialMessages: self.messages,
                        environment: env
                    )

                    let splitFinal = ChatPromptBuilder.splitReasoning(
                        from: result.content ?? "No response received.")
                    historyManager.append(
                        ChatMessage(
                            role: .assistant,
                            content: splitFinal.content,
                            context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
                        )
                    )
                    isSending = false
                    return
                }

                if currentMode == .agent,
                    currentResponse.toolCalls?.isEmpty ?? true,
                    let content = currentResponse.content,
                    ChatPromptBuilder.shouldForceToolFollowup(content: content),
                    let lastUserMessage = self.messages.last(where: { $0.role == .user })
                {

                    let followupSystem = ChatMessage(
                        role: .system,
                        content:
                            "You indicated you will implement changes, but you returned no tool calls. In Agent mode, you MUST now proceed by calling the appropriate tools. Return tool calls now."
                    )

                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [followupSystem, lastUserMessage],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                    .get()
                }

                var toolIteration = 0
                let maxIterations = (currentMode == .agent) ? 12 : 5

                while let toolCalls = currentResponse.toolCalls,
                    !toolCalls.isEmpty && toolIteration < maxIterations
                {
                    toolIteration += 1

                    await AIToolTraceLogger.shared.log(type: "chat.tool_loop_iteration", data: [
                        "mode": self.currentMode.rawValue,
                        "iteration": toolIteration,
                        "toolCalls": toolCalls.count
                    ])

                    let split = ChatPromptBuilder.splitReasoning(
                        from: currentResponse.content ?? "")
                    let assistantMsg = ChatMessage(
                        role: .assistant,
                        content: split.content,
                        context: ChatMessageContentContext(reasoning: split.reasoning),
                        tool: ChatMessageToolContext(toolCalls: toolCalls)
                    )
                    historyManager.append(assistantMsg)

                    let conversationId = self.conversationId
                    let toolCallsCount = toolCalls.count
                    let toolCallsMetadata = toolCalls.map {
                        [
                            "id": $0.id,
                            "name": $0.name,
                        ]
                    }

                    Task.detached(priority: .utility) {
                        await AppLogger.shared.info(
                            category: .conversation, message: "chat.assistant_tool_calls",
                            metadata: [
                                "conversationId": conversationId,
                                "toolCalls": toolCallsCount,
                            ])
                        await ConversationLogStore.shared.append(
                            conversationId: conversationId,
                            type: "chat.assistant_tool_calls",
                            data: [
                                "content": split.content,
                                "toolCalls": toolCallsMetadata,
                            ]
                        )
                    }

                    let toolResults = await toolExecutor.executeBatch(
                        toolCalls, availableTools: availableTools,
                        conversationId: self.conversationId
                    ) { progressMsg in
                        if progressMsg.isToolExecution {
                            self.historyManager.upsertToolExecutionMessage(progressMsg)
                        } else {
                            self.historyManager.append(progressMsg)
                        }
                    }

                    for msg in toolResults {
                        if msg.isToolExecution {
                            self.historyManager.upsertToolExecutionMessage(msg)
                        } else {
                            self.historyManager.append(msg)
                        }
                    }

                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages,
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                    .get()
                }

                if ChatPromptBuilder.needsReasoningFormatCorrection(
                    text: currentResponse.content ?? "")
                {
                    let correctionSystem = ChatMessage(
                        role: .system,
                        content:
                            "Your <ide_reasoning> block must include ALL four sections: Analyze, Research, Plan, Reflect."
                    )
                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [correctionSystem],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                    .get()
                }

                if ChatPromptBuilder.isLowQualityReasoning(text: currentResponse.content ?? "") {
                    let correctionSystem = ChatMessage(
                        role: .system,
                        content:
                            "Your <ide_reasoning> block is too vague (placeholders like '...' are not allowed). Provide concise, concrete bullet points for EACH section: Analyze, Research, Plan, Reflect. If unknown, write 'N/A' and state what information is needed."
                    )
                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [correctionSystem],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                    .get()
                }

                let splitFinal = ChatPromptBuilder.splitReasoning(
                    from: currentResponse.content ?? "No response received.")
                historyManager.append(
                    ChatMessage(
                        role: .assistant,
                        content: splitFinal.content,
                        context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
                    )
                )

                let hasReasoning = (splitFinal.reasoning?.isEmpty == false)

                let contentLength = splitFinal.content.count
                let reasoningText = splitFinal.reasoning

                Task.detached(priority: .utility) {
                    await AppLogger.shared.info(
                        category: .conversation, message: "chat.assistant_message",
                        metadata: [
                            "conversationId": conversationId,
                            "contentLength": contentLength,
                            "hasReasoning": hasReasoning,
                        ])
                    await ConversationLogStore.shared.append(
                        conversationId: conversationId,
                        type: "chat.assistant_message",
                        data: [
                            "content": splitFinal.content,
                            "reasoning": reasoningText as Any,
                        ]
                    )
                }
                isSending = false

            } catch {
                let conversationId = self.conversationId
                let errorDescription = error.localizedDescription
                Task.detached(priority: .utility) {
                    await AppLogger.shared.error(
                        category: .error, message: "chat.error",
                        metadata: [
                            "conversationId": conversationId,
                            "error": errorDescription,
                        ])
                    await ConversationLogStore.shared.append(
                        conversationId: conversationId,
                        type: "chat.error",
                        data: [
                            "error": errorDescription
                        ]
                    )
                }
                await MainActor.run {
                    self.errorManager.handle(.aiServiceError(error.localizedDescription))
                    self.error = "Failed to get AI response: \(error.localizedDescription)"
                    self.isSending = false
                }
            }
        }
    }

    private func sendMessageWithRetry(
        messages: [ChatMessage],
        context: String?,
        tools: [AITool],
        mode: AIMode,
        projectRoot: URL
    ) async -> Result<AIServiceResponse, AppError> {
        let maxAttempts = 3
        var lastError: AppError?
        for attempt in 1...maxAttempts {
            let augmentedContext = await ContextBuilder.buildContext(
                userInput: messages.last(where: { $0.role == .user })?.content ?? "",
                explicitContext: context,
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
                if attempt < maxAttempts { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
        return .failure(lastError ?? .unknown("ConversationManager: sendMessageWithRetry failed"))
    }

    func clearConversation() {
        historyManager.clear()
        cancelledToolCallIds.removeAll()
    }

    func startNewConversation() {
        let oldConversationId = conversationId
        conversationId = UUID().uuidString

        hasStartedConversation = true
        persistConversationId(projectRoot: projectRoot, conversationId: conversationId)

        historyManager.clear()
        cancelledToolCallIds.removeAll()

        Task.detached(priority: .utility) {
            let initialMode = await self.currentMode.rawValue
            let initialProjectRootPath = await self.projectRoot.path
            let newConversationId = await self.conversationId

            await AppLogger.shared.info(
                category: .conversation, message: "conversation.start",
                metadata: [
                    "conversationId": newConversationId,
                    "mode": initialMode,
                    "projectRoot": initialProjectRootPath,
                    "previousConversationId": oldConversationId,
                ])
            await ConversationLogStore.shared.append(
                conversationId: newConversationId,
                type: "conversation.start",
                data: [
                    "mode": initialMode,
                    "projectRoot": initialProjectRootPath,
                    "previousConversationId": oldConversationId,
                ]
            )

            await ConversationIndexStore.shared.appendStart(
                conversationId: newConversationId,
                mode: initialMode,
                projectRootPath: initialProjectRootPath
            )
        }
    }

    func cancelToolCall(id: String) {
        cancelledToolCallIds.insert(id)
        // Find the specific tool execution message and mark it as failed/cancelled
        historyManager.updateMessageStatus(
            toolCallId: id, status: .failed, content: "Cancelled by user")
    }

    func explainCode(_ code: String) {
        isSending = true
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await aiService.explainCode(code)
                self.historyManager.append(
                    ChatMessage(
                        role: .user,
                        content: "Explain this code",
                        context: ChatMessageContentContext(codeContext: code)
                    )
                )
                self.historyManager.append(ChatMessage(role: .assistant, content: response))
                self.isSending = false
            } catch {
                self.error = "Failed to explain code: \(error.localizedDescription)"
                self.isSending = false
            }
        }
    }

    func refactorCode(_ code: String, instructions: String) {
        isSending = true
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await aiService.refactorCode(code, instructions: instructions)
                self.historyManager.append(
                    ChatMessage(
                        role: .user,
                        content: "Refactor this code: \(instructions)",
                        context: ChatMessageContentContext(codeContext: code)
                    )
                )
                self.historyManager.append(
                    ChatMessage(
                        role: .assistant,
                        content: "Here's the refactored code:",
                        context: ChatMessageContentContext(codeContext: response)
                    )
                )
                self.isSending = false
            } catch {
                self.error = "Failed to refactor code: \(error.localizedDescription)"
                self.isSending = false
            }
        }
    }
}
