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
    struct Dependencies {
        let services: ServiceDependencies
        let environment: EnvironmentDependencies
    }

    struct ServiceDependencies {
        let aiService: AIService
        let errorManager: ErrorManagerProtocol
        let fileSystemService: FileSystemService
        let fileEditorService: (any FileEditorServiceProtocol)?
    }

    struct EnvironmentDependencies {
        let workspaceService: WorkspaceServiceProtocol
        let eventBus: EventBusProtocol
        let projectRoot: URL?
        let codebaseIndex: CodebaseIndexProtocol?
    }

    private struct UserMessageContext {
        let text: String
        let hasSelectionContext: Bool
        let message: ChatMessage
    }

    @Published var currentInput: String = ""
    @Published var isSending: Bool = false
    @Published var error: String?
    @Published var currentMode: AIMode = .chat
    @Published var cancelledToolCallIds: Set<String> = []

    private let historyManager: ChatHistoryManager
    private let historyCoordinator: ChatHistoryCoordinator
    private let toolExecutor: AIToolExecutor
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private var aiService: AIService
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let sendCoordinator: ConversationSendCoordinator
    private let errorManager: ErrorManagerProtocol
    private let fileSystemService: FileSystemService
    private weak var fileEditorService: (any FileEditorServiceProtocol)?
    private let workspaceService: WorkspaceServiceProtocol
    private let eventBus: EventBusProtocol
    private var codebaseIndex: CodebaseIndexProtocol?
    private var projectRoot: URL
    private let conversationLogger: ConversationLogger
    private lazy var toolProvider = ConversationToolProvider(
        fileSystemService: fileSystemService,
        eventBus: eventBus,
        aiServiceProvider: { [unowned self] in self.aiService },
        codebaseIndexProvider: { [unowned self] in self.codebaseIndex },
        projectRootProvider: { [unowned self] in self.projectRoot }
    )
    private var cancellables = Set<AnyCancellable>()

    var messages: [ChatMessage] {
        historyCoordinator.messages
    }

    var currentConversationId: String {
        historyCoordinator.currentConversationId
    }

    private var conversationId: String {
        historyCoordinator.currentConversationId
    }

    private var pathValidator: PathValidator {
        workspaceService.makePathValidator(projectRoot: projectRoot)
    }

    private var availableTools: [AITool] {
        toolProvider.availableTools(mode: currentMode, pathValidator: pathValidator)
    }

    init(dependencies: Dependencies) {
        self.aiService = dependencies.services.aiService
        self.errorManager = dependencies.services.errorManager
        self.fileSystemService = dependencies.services.fileSystemService
        self.fileEditorService = dependencies.services.fileEditorService
        self.workspaceService = dependencies.environment.workspaceService
        self.eventBus = dependencies.environment.eventBus
        let root = dependencies.environment.projectRoot ?? FileManager.default.temporaryDirectory
        self.projectRoot = root
        self.codebaseIndex = dependencies.environment.codebaseIndex

        self.aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: dependencies.services.aiService,
            codebaseIndex: dependencies.environment.codebaseIndex
        )

        self.historyManager = ChatHistoryManager()
        self.historyCoordinator = ChatHistoryCoordinator(
            historyManager: historyManager,
            projectRoot: root
        )
        let fileEditorServiceProvider = fileEditorService
        self.toolExecutor = AIToolExecutor(
            fileSystemService: dependencies.services.fileSystemService,
            errorManager: dependencies.services.errorManager,
            projectRoot: root,
            defaultFilePathProvider: { [weak fileEditorServiceProvider] in
                fileEditorServiceProvider?.selectedFile
            }
        )

        self.toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)

        self.sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        self.conversationLogger = ConversationLogger()

        initializeLogging(root: root)
        setupObservation()
        startTraceLogging()
        configureLoggingStores(root: root)
    }

    private func setupObservation() {
        historyManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func initializeLogging(root: URL) {
        conversationLogger.initializeProjectRoot(root)
    }

    private func startTraceLogging() {
        Task.detached(priority: .utility) {
            let logPath = await AIToolTraceLogger.shared.currentLogFilePath()
            await self.conversationLogger.logTraceStart(
                mode: await self.currentMode.rawValue,
                projectRootPath: await self.projectRoot.path,
                logPath: logPath
            )
        }
    }

    private func configureLoggingStores(root: URL) {
        Task.detached(priority: .utility) {
            await AppLogger.shared.setProjectRoot(root)
            await ConversationLogStore.shared.setProjectRoot(root)
            await ExecutionLogStore.shared.setProjectRoot(root)
            await ConversationIndexStore.shared.setProjectRoot(root)
            await ConversationPlanStore.shared.setProjectRoot(root)
            await PatchSetStore.shared.setProjectRoot(root)
            await CheckpointManager.shared.setProjectRoot(root)
            await OrchestrationRunStore.shared.setProjectRoot(root)
        }
    }

    func updateAIService(_ newService: AIService) {
        self.aiService = newService
        aiInteractionCoordinator.updateAIService(newService)
    }

    func updateCodebaseIndex(_ newIndex: CodebaseIndexProtocol?) {
        self.codebaseIndex = newIndex
        aiInteractionCoordinator.updateCodebaseIndex(newIndex)
    }

    func updateProjectRoot(_ newRoot: URL) {
        if projectRoot.standardizedFileURL == newRoot.standardizedFileURL {
            return
        }

        projectRoot = newRoot

        historyCoordinator.updateProjectRoot(
            newRoot,
            shouldStartConversationLog: true,
            onStartConversation: { _, _, _ in
                _ = ()
            }
        )

        conversationLogger.initializeProjectRoot(newRoot)
        conversationLogger.logConversationStart(
            conversationId: self.conversationId,
            mode: self.currentMode.rawValue,
            projectRootPath: newRoot.path
        )
    }

    func sendMessage() {
        sendMessage(context: nil)
    }

    func sendMessage(context: String? = nil) {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userContext = buildUserMessageContext(context: context)
        logUserMessage(userContext)
        historyCoordinator.append(userContext.message)
        resetInputState()
        startSendTask(userContext: userContext, explicitContext: context)
    }

    private func buildUserMessageContext(context: String?) -> UserMessageContext {
        let userMessageText = currentInput
        let hasSelectionContext = (context?.isEmpty == false)
        let userMessage = ChatMessage(
            role: .user,
            content: currentInput,
            context: ChatMessageContentContext(codeContext: context)
        )
        return UserMessageContext(
            text: userMessageText,
            hasSelectionContext: hasSelectionContext,
            message: userMessage
        )
    }

    private func logUserMessage(_ context: UserMessageContext) {
        conversationLogger.logUserMessage(
            ConversationUserMessageLogContext(
                identity: ConversationUserMessageLogContext.Identity(
                    conversationId: conversationId,
                    projectRootPath: projectRoot.path
                ),
                details: ConversationUserMessageLogContext.MessageDetails(
                    text: context.text,
                    mode: currentMode.rawValue,
                    hasSelectionContext: context.hasSelectionContext
                )
            )
        )
    }

    private func resetInputState() {
        currentInput = ""
        isSending = true
        error = nil
    }

    private func startSendTask(userContext: UserMessageContext, explicitContext: String?) {
        Task { [weak self] in
            guard let self = self else { return }
            let runId = UUID().uuidString

            let tools = (self.currentMode == .chat) ? [] : self.availableTools

            let provider = AIProviderSettingsStore().load()
            let enableAssistantStreaming = tools.isEmpty || (self.currentMode == .agent && provider == .local)
            let assistantStreamingMessageId: UUID? = enableAssistantStreaming ? UUID() : nil
            if let assistantStreamingMessageId {
                historyCoordinator.append(
                    ChatMessage(
                        id: assistantStreamingMessageId,
                        role: .assistant,
                        content: "Generating…"
                    )
                )
            }

            do {
                conversationLogger.logAIRequestStart(
                    mode: self.currentMode.rawValue,
                    historyCount: self.messages.count
                )

                try await self.sendCoordinator.send(
                    SendRequest(
                        userInput: userContext.text,
                        explicitContext: explicitContext,
                        mode: self.currentMode,
                        projectRoot: self.projectRoot,
                        conversationId: self.conversationId,
                        runId: runId,
                        availableTools: tools,
                        cancelledToolCallIds: { [cancelledIds = self.cancelledToolCallIds] in cancelledIds },
                        qaReviewEnabled: self.currentMode == .agent,
                        assistantStreamingMessageId: assistantStreamingMessageId,
                        enableAssistantStreaming: enableAssistantStreaming
                    )
                )

                self.isSending = false
            } catch {
                handleSendFailure(error)
            }
        }
    }

    private func handleSendFailure(_ error: Error) {
        conversationLogger.logChatError(
            conversationId: conversationId,
            errorDescription: error.localizedDescription
        )
        Task { @MainActor in
            errorManager.handle(.aiServiceError(error.localizedDescription))
            self.error = "Failed to get AI response: \(error.localizedDescription)"
            isSending = false
        }
    }

    func clearConversation() {
        historyCoordinator.clearConversation()
        cancelledToolCallIds.removeAll()
    }

    func startNewConversation() {
        let oldConversationId = conversationId
        let ids = historyCoordinator.startNewConversation(projectRoot: projectRoot)
        cancelledToolCallIds.removeAll()

        conversationLogger.logConversationStart(
            conversationId: ids.newConversationId,
            mode: self.currentMode.rawValue,
            projectRootPath: self.projectRoot.path,
            previousConversationId: oldConversationId
        )
    }

    func cancelToolCall(id: String) {
        cancelledToolCallIds.insert(id)
        // Find the specific tool execution message and mark it as failed/cancelled
        historyCoordinator.updateMessageStatus(toolCallId: id, status: .failed, content: "Cancelled by user")
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
