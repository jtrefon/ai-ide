//
//  ConversationManager.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation
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
        let activityCoordinator: AgentActivityCoordinating?
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

    private struct ConversationSessionSnapshot {
        let messages: [ChatMessage]
        let mode: AIMode
        let input: String
        let livePreview: String
        let liveStatusPreview: String
    }

    @Published var currentInput: String = ""
    @Published var isSending: Bool = false
    @Published var error: String?
    @Published var currentMode: AIMode = .chat
    @Published var cancelledToolCallIds: Set<String> = []
    @Published private(set) var liveModelOutputPreview: String = ""
    @Published private(set) var liveModelOutputStatusPreview: String = ""
    @Published private(set) var isLiveModelOutputPreviewVisible: Bool = true
    @Published private(set) var conversationTabs: [ConversationTabItem] = []

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
    private let settingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)
    private let activityCoordinator: AgentActivityCoordinating?
    /// Token for the current API sending activity
    private var apiSendingActivityToken: AgentActivityToken?
    private lazy var toolProvider = ConversationToolProvider(
        fileSystemService: fileSystemService,
        eventBus: eventBus,
        aiServiceProvider: { [unowned self] in self.aiService },
        codebaseIndexProvider: { [unowned self] in self.codebaseIndex },
        projectRootProvider: { [unowned self] in self.projectRoot }
    )
    private var cancellables = Set<AnyCancellable>()

    private var activeStreamingRunId: String?
    private var draftAssistantMessageId: UUID?
    private var draftAssistantText: String = ""
    private var pendingStreamingBuffer: String = ""
    private var streamingRenderTask: Task<Void, Never>?
    private let streamingRenderIntervalNanoseconds: UInt64 = 16_000_000
    private let maxStreamingCharactersPerTick = 8
    private var activeSendTask: Task<Void, Never>?
    private let maxPreviewCharacters = 12_000
    private let maxStatusPreviewCharacters = 4_000
    private var currentSessionId: String
    private var conversationSessionOrder: [String]
    private var conversationSessionSnapshots: [String: ConversationSessionSnapshot]

    var messages: [ChatMessage] {
        historyCoordinator.messages
    }

    var currentConversationId: String {
        currentSessionId
    }

    private var conversationId: String {
        currentSessionId
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
        self.activityCoordinator = dependencies.services.activityCoordinator
        self.workspaceService = dependencies.environment.workspaceService
        self.eventBus = dependencies.environment.eventBus
        let root = dependencies.environment.projectRoot ?? FileManager.default.temporaryDirectory
        self.projectRoot = root
        self.codebaseIndex = dependencies.environment.codebaseIndex

        self.aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: dependencies.services.aiService,
            codebaseIndex: dependencies.environment.codebaseIndex,
            eventBus: dependencies.environment.eventBus
        )

        self.historyManager = ChatHistoryManager()
        self.historyCoordinator = ChatHistoryCoordinator(
            historyManager: historyManager,
            projectRoot: root
        )
        let initialConversationId = historyCoordinator.currentConversationId
        self.currentSessionId = initialConversationId
        self.conversationSessionOrder = [initialConversationId]
        self.conversationSessionSnapshots = [
            initialConversationId: ConversationSessionSnapshot(
                messages: historyCoordinator.messages,
                mode: .chat,
                input: "",
                livePreview: "",
                liveStatusPreview: ""
            )
        ]
        let fileEditorServiceProvider = fileEditorService
        self.toolExecutor = AIToolExecutor(
            fileSystemService: dependencies.services.fileSystemService,
            errorManager: dependencies.services.errorManager,
            projectRoot: root,
            defaultFilePathProvider: { [weak fileEditorServiceProvider] in
                fileEditorServiceProvider?.selectedFile
            },
            activityCoordinator: dependencies.services.activityCoordinator
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
        setupPowerManagementObservation()
        setupStreamingSubscriptions()
        startTraceLogging()
        configureLoggingStores(root: root)
        refreshConversationTabs()
    }

    private func refreshConversationTabs() {
        conversationTabs = conversationSessionOrder.enumerated().map { index, id in
            ConversationTabItem(id: id, title: "Chat \(index + 1)")
        }
    }

    private func saveCurrentSessionSnapshot() {
        conversationSessionSnapshots[currentSessionId] = ConversationSessionSnapshot(
            messages: historyCoordinator.messages,
            mode: currentMode,
            input: currentInput,
            livePreview: liveModelOutputPreview,
            liveStatusPreview: liveModelOutputStatusPreview
        )
    }

    private func restoreSession(_ sessionId: String) {
        let snapshot = conversationSessionSnapshots[sessionId] ?? ConversationSessionSnapshot(
            messages: [],
            mode: .chat,
            input: "",
            livePreview: "",
            liveStatusPreview: ""
        )
        currentSessionId = sessionId
        historyCoordinator.switchConversation(to: sessionId, projectRoot: projectRoot)
        historyCoordinator.replaceAllMessages(with: snapshot.messages)
        currentMode = snapshot.mode
        currentInput = snapshot.input
        setLiveModelPreview(snapshot.livePreview)
        setLiveModelStatusPreview(snapshot.liveStatusPreview)
        cancelledToolCallIds.removeAll()
    }

    private func setupStreamingSubscriptions() {
        eventBus
            .subscribe(to: LocalModelStreamingChunkEvent.self) { [weak self] event in
                guard let self else { return }
                self.handleLocalModelStreamingChunk(event)
            }
            .store(in: &cancellables)

        eventBus
            .subscribe(to: LocalModelStreamingStatusEvent.self) { [weak self] event in
                guard let self else { return }
                self.handleLocalModelStreamingStatus(event)
            }
            .store(in: &cancellables)
    }

    private func handleLocalModelStreamingChunk(_ event: LocalModelStreamingChunkEvent) {
        guard let runId = activeStreamingRunId, runId == event.runId else { return }
        guard let draftId = draftAssistantMessageId else { return }
        guard !event.chunk.isEmpty else { return }

        appendToLiveModelPreview(event.chunk)
        pendingStreamingBuffer.append(event.chunk)
        startStreamingRenderLoopIfNeeded(draftId: draftId)
    }

    private func startStreamingRenderLoopIfNeeded(draftId: UUID) {
        guard streamingRenderTask == nil else { return }
        streamingRenderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.streamingRenderTask = nil }
            while self.activeStreamingRunId != nil {
                if self.pendingStreamingBuffer.isEmpty {
                    try? await Task.sleep(nanoseconds: self.streamingRenderIntervalNanoseconds)
                    continue
                }

                let delta = self.dequeueStreamingDelta()
                guard !delta.isEmpty else {
                    try? await Task.sleep(nanoseconds: self.streamingRenderIntervalNanoseconds)
                    continue
                }
                guard self.historyCoordinator.getDraftMessage(id: draftId) != nil else { break }

                self.draftAssistantText.append(delta)
                let displayText = ChatPromptBuilder.contentForDisplay(from: self.draftAssistantText)
                let draftTimestamp = self.historyCoordinator.getDraftMessage(id: draftId)?.timestamp ?? Date()

                self.historyCoordinator.upsertMessage(
                    ChatMessage(
                        id: draftId,
                        role: .assistant,
                        content: displayText.isEmpty ? "Generating..." : displayText,
                        timestamp: draftTimestamp,
                        isDraft: true
                    )
                )

                try? await Task.sleep(nanoseconds: self.streamingRenderIntervalNanoseconds)
            }
        }
    }

    private func dequeueStreamingDelta() -> String {
        guard !pendingStreamingBuffer.isEmpty else { return "" }
        let take = min(maxStreamingCharactersPerTick, pendingStreamingBuffer.count)
        let splitIndex = pendingStreamingBuffer.index(
            pendingStreamingBuffer.startIndex,
            offsetBy: take
        )
        let chunk = String(pendingStreamingBuffer[..<splitIndex])
        pendingStreamingBuffer.removeSubrange(pendingStreamingBuffer.startIndex..<splitIndex)
        return chunk
    }

    private func flushPendingStreamingBuffer() {
        guard let draftId = draftAssistantMessageId, !pendingStreamingBuffer.isEmpty else { return }
        guard historyCoordinator.getDraftMessage(id: draftId) != nil else {
            pendingStreamingBuffer = ""
            return
        }
        draftAssistantText.append(pendingStreamingBuffer)
        pendingStreamingBuffer = ""
        let displayText = ChatPromptBuilder.contentForDisplay(from: draftAssistantText)
        let draftTimestamp = historyCoordinator.getDraftMessage(id: draftId)?.timestamp ?? Date()
        historyCoordinator.upsertMessage(
            ChatMessage(
                id: draftId,
                role: .assistant,
                content: displayText.isEmpty ? "Generating..." : displayText,
                timestamp: draftTimestamp,
                isDraft: true
            )
        )
    }

    private func handleLocalModelStreamingStatus(_ event: LocalModelStreamingStatusEvent) {
        guard let runId = activeStreamingRunId, runId == event.runId else { return }
        appendToLiveModelStatusPreview(event.message)
    }

    private func setupObservation() {
        historyManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Observe isSending state to prevent system sleep during agent activity
    /// Uses AgentActivityCoordinator for reference-counted power management
    private func setupPowerManagementObservation() {
        $isSending
            .removeDuplicates()
            .sink { [weak self] isSending in
                guard let self, let coordinator = self.activityCoordinator else { return }

                if isSending {
                    // Begin API sending activity - token will be released when sending ends
                    self.apiSendingActivityToken = coordinator.beginActivity(type: .apiSending)
                } else {
                    // End API sending activity
                    self.apiSendingActivityToken?.end()
                    self.apiSendingActivityToken = nil
                }
            }
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
            // CRITICAL: Set project root for all loggers including AI trace
            await AIToolTraceLogger.shared.setProjectRoot(root)
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

        saveCurrentSessionSnapshot()

        // Clear conversation history when switching to a new project
        // This ensures the chat is fresh for the new project
        clearConversation()

        historyCoordinator.updateProjectRoot(
            newRoot,
            shouldStartConversationLog: true,
            onStartConversation: { _, _, _ in
                _ = ()
            }
        )

        let migratedSessionId = historyCoordinator.currentConversationId
        currentSessionId = migratedSessionId
        conversationSessionOrder = [migratedSessionId]
        conversationSessionSnapshots = [
            migratedSessionId: ConversationSessionSnapshot(
                messages: historyCoordinator.messages,
                mode: currentMode,
                input: currentInput,
                livePreview: liveModelOutputPreview,
                liveStatusPreview: liveModelOutputStatusPreview
            )
        ]
        refreshConversationTabs()

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

    private func appendToLiveModelPreview(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        liveModelOutputPreview.append(chunk)
        if liveModelOutputPreview.count > maxPreviewCharacters {
            liveModelOutputPreview = String(liveModelOutputPreview.suffix(maxPreviewCharacters))
        }
    }

    private func setLiveModelPreview(_ text: String) {
        if text.count > maxPreviewCharacters {
            liveModelOutputPreview = String(text.suffix(maxPreviewCharacters))
        } else {
            liveModelOutputPreview = text
        }
    }

    private func appendToLiveModelStatusPreview(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if liveModelOutputStatusPreview.isEmpty {
            liveModelOutputStatusPreview = trimmed
        } else {
            liveModelOutputStatusPreview += "\n" + trimmed
        }

        if liveModelOutputStatusPreview.count > maxStatusPreviewCharacters {
            liveModelOutputStatusPreview = String(liveModelOutputStatusPreview.suffix(maxStatusPreviewCharacters))
        }
    }

    private func setLiveModelStatusPreview(_ text: String) {
        if text.count > maxStatusPreviewCharacters {
            liveModelOutputStatusPreview = String(text.suffix(maxStatusPreviewCharacters))
        } else {
            liveModelOutputStatusPreview = text
        }
    }

    private func resetStreamingDraftState() {
        activeStreamingRunId = nil
        draftAssistantMessageId = nil
        draftAssistantText = ""
        pendingStreamingBuffer = ""
        streamingRenderTask?.cancel()
        streamingRenderTask = nil
    }

    private func resetConversationInteractionState() {
        resetStreamingDraftState()
        isSending = false
        error = nil
    }

    private func cancelActiveSendTask() {
        activeSendTask?.cancel()
        activeSendTask = nil
    }

    private func startSendTask(userContext: UserMessageContext, explicitContext: String?) {
        cancelActiveSendTask()
        activeSendTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.activeSendTask = nil }

            let runId = UUID().uuidString

            // Create a draft message that will be updated during streaming
            let draftMessage = ChatMessage(
                role: .assistant,
                content: "Generating...",
                isDraft: true
            )
            self.draftAssistantMessageId = draftMessage.id
            self.draftAssistantText = ""
            self.activeStreamingRunId = runId
            self.setLiveModelPreview("Waiting for model output…")
            self.setLiveModelStatusPreview("Run started: awaiting streamed output and tool calls…")
            self.historyCoordinator.append(draftMessage)

            let tools = (self.currentMode == .chat) ? [] : self.availableTools

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
                        qaReviewEnabled: self.currentMode == .agent && self.settingsStore.bool(forKey: AppConstantsStorage.agentQAReviewEnabledKey, default: false),
                        draftAssistantMessageId: self.draftAssistantMessageId
                    )
                )

                self.flushPendingStreamingBuffer()
                if let finalAssistantMessage = self.messages.last(where: { $0.role == .assistant && !$0.isDraft }) {
                    self.setLiveModelPreview(finalAssistantMessage.content)
                }
                self.appendToLiveModelStatusPreview("Run completed.")
                self.resetStreamingDraftState()
                self.isSending = false
            } catch {
                // Clean up draft message on error
                if let draftId = self.draftAssistantMessageId {
                    self.historyCoordinator.removeDraftMessage(id: draftId)
                }
                self.resetStreamingDraftState()
                if error is CancellationError {
                    self.setLiveModelPreview("Generation cancelled.")
                    self.appendToLiveModelStatusPreview("Run cancelled.")
                    self.isSending = false
                    return
                }
                handleSendFailure(error)
            }
        }
    }

    private func handleSendFailure(_ error: Error) {
        conversationLogger.logChatError(
            conversationId: conversationId,
            errorDescription: error.localizedDescription
        )
        // Add error message to chat so user knows what happened
        let errorMessage = ChatMessage(
            role: .assistant,
            content: "I encountered an error: \(error.localizedDescription). Please try again."
        )
        historyCoordinator.append(errorMessage)
        setLiveModelPreview("Error: \(error.localizedDescription)")
        appendToLiveModelStatusPreview("Run failed: \(error.localizedDescription)")
        
        Task { @MainActor in
            errorManager.handle(.aiServiceError(error.localizedDescription))
            self.error = "Failed to get AI response: \(error.localizedDescription)"
            isSending = false
        }
    }

    func clearConversation() {
        cancelActiveSendTask()
        resetConversationInteractionState()
        currentInput = ""
        setLiveModelPreview("")
        setLiveModelStatusPreview("")
        historyCoordinator.clearConversation()
        cancelledToolCallIds.removeAll()
    }

    func startNewConversation() {
        cancelActiveSendTask()
        resetConversationInteractionState()
        saveCurrentSessionSnapshot()
        currentInput = ""
        setLiveModelPreview("")
        setLiveModelStatusPreview("")

        let oldConversationId = currentSessionId
        let newConversationId = UUID().uuidString
        conversationSessionOrder.append(newConversationId)
        conversationSessionSnapshots[newConversationId] = ConversationSessionSnapshot(
            messages: [],
            mode: currentMode,
            input: "",
            livePreview: "",
            liveStatusPreview: ""
        )
        restoreSession(newConversationId)
        refreshConversationTabs()
        cancelledToolCallIds.removeAll()

        conversationLogger.logConversationStart(
            conversationId: newConversationId,
            mode: self.currentMode.rawValue,
            projectRootPath: self.projectRoot.path,
            previousConversationId: oldConversationId
        )
    }

    func switchConversation(to id: String) {
        guard id != currentSessionId else { return }
        guard conversationSessionSnapshots[id] != nil else { return }

        cancelActiveSendTask()
        resetConversationInteractionState()
        saveCurrentSessionSnapshot()
        restoreSession(id)
        refreshConversationTabs()
    }

    func closeConversation(id: String) {
        guard conversationSessionOrder.count > 1 else { return }
        guard let closingIndex = conversationSessionOrder.firstIndex(of: id) else { return }

        cancelActiveSendTask()
        if id == currentSessionId {
            saveCurrentSessionSnapshot()
        }

        conversationSessionOrder.remove(at: closingIndex)
        conversationSessionSnapshots[id] = nil

        if id == currentSessionId {
            let fallbackIndex = min(closingIndex, conversationSessionOrder.count - 1)
            let fallbackId = conversationSessionOrder[fallbackIndex]
            restoreSession(fallbackId)
        }

        refreshConversationTabs()
    }

    func stopGeneration() {
        guard isSending else { return }
        cancelActiveSendTask()
        resetStreamingDraftState()
        isSending = false
        setLiveModelPreview("Generation stopped by user.")
        appendToLiveModelStatusPreview("Run stopped by user.")
    }

    func cancelToolCall(id: String) {
        cancelledToolCallIds.insert(id)
        // Find the specific tool execution message and mark it as failed/cancelled
        historyCoordinator.updateMessageStatus(toolCallId: id, status: .failed, content: "Cancelled by user")
    }

    func explainCode(_ code: String) {
        isSending = true
        setLiveModelPreview("")
        setLiveModelStatusPreview("")
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await aiService.explainCode(code)
                self.setLiveModelPreview(response)
                self.appendToLiveModelStatusPreview("Explain code completed.")
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
                self.setLiveModelPreview("Error: \(error.localizedDescription)")
                self.appendToLiveModelStatusPreview("Explain code failed: \(error.localizedDescription)")
                self.isSending = false
            }
        }
    }

    func refactorCode(_ code: String, instructions: String) {
        isSending = true
        setLiveModelPreview("")
        setLiveModelStatusPreview("")
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await aiService.refactorCode(code, instructions: instructions)
                self.setLiveModelPreview(response)
                self.appendToLiveModelStatusPreview("Refactor code completed.")
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
                self.setLiveModelPreview("Error: \(error.localizedDescription)")
                self.appendToLiveModelStatusPreview("Refactor code failed: \(error.localizedDescription)")
                self.isSending = false
            }
        }
    }
}
