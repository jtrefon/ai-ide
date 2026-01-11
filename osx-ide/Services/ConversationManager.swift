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

    init(
        aiService: AIService,
        errorManager: ErrorManagerProtocol,
        fileSystemService: FileSystemService = FileSystemService(),
        fileEditorService: (any FileEditorServiceProtocol)? = nil,
        workspaceService: WorkspaceServiceProtocol,
        eventBus: EventBusProtocol,
        projectRoot: URL? = nil,
        codebaseIndex: CodebaseIndexProtocol? = nil
    ) {
        self.aiService = aiService
        self.errorManager = errorManager
        self.fileSystemService = fileSystemService
        self.fileEditorService = fileEditorService
        self.workspaceService = workspaceService
        self.eventBus = eventBus
        let root = projectRoot ?? FileManager.default.temporaryDirectory
        self.projectRoot = root
        self.codebaseIndex = codebaseIndex

        self.aiInteractionCoordinator = AIInteractionCoordinator(aiService: aiService, codebaseIndex: codebaseIndex)

        self.historyManager = ChatHistoryManager()
        self.historyCoordinator = ChatHistoryCoordinator(
            historyManager: historyManager,
            projectRoot: root
        )
        let fileEditorServiceProvider = fileEditorService
        self.toolExecutor = AIToolExecutor(
            fileSystemService: fileSystemService,
            errorManager: errorManager,
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
            onStartConversation: { _, _, _ in }
        )

        let newRootPath = newRoot.path
        let initialMode = self.currentMode.rawValue
        let initialConversationId = self.conversationId

        let shouldStartConversation = false

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

            await AppLogger.shared.info(
                category: .conversation, message: "conversation.start",
                metadata: [
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
        historyCoordinator.append(userMessage)

        currentInput = ""
        isSending = true
        error = nil

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let modeRawValue = self.currentMode.rawValue
                let projectRootPath = self.projectRoot.path
                let conversationId = self.conversationId
                let historyCount = self.messages.count

                Task.detached(priority: .utility) {
                    await AIToolTraceLogger.shared.log(
                        type: "chat.ai_request_start",
                        data: [
                            "mode": modeRawValue,
                            "historyCount": historyCount,
                        ])
                }

                try await self.sendCoordinator.send(
                    userInput: userMessageText,
                    explicitContext: context,
                    mode: self.currentMode,
                    projectRoot: self.projectRoot,
                    conversationId: self.conversationId,
                    availableTools: self.availableTools,
                    cancelledToolCallIds: { [weak self] in self?.cancelledToolCallIds ?? [] }
                )

                self.isSending = false

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

    func clearConversation() {
        historyCoordinator.clearConversation()
        cancelledToolCallIds.removeAll()
    }

    func startNewConversation() {
        let oldConversationId = conversationId
        let ids = historyCoordinator.startNewConversation(projectRoot: projectRoot)
        cancelledToolCallIds.removeAll()

        Task.detached(priority: .utility) {
            let initialMode = await self.currentMode.rawValue
            let initialProjectRootPath = await self.projectRoot.path
            let newConversationId = ids.newConversationId

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
