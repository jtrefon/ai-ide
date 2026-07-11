//
//  ConversationManager.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation
import Combine
import SwiftUI

// MARK: - ConversationManager

@MainActor
final class ConversationManager: ObservableObject, ConversationManagerProtocol {

    // MARK: - Nested Types

    struct Dependencies {
        let services: ServiceDependencies
        let environment: EnvironmentDependencies
    }

    struct ServiceDependencies {
        let aiService: AIService
        let errorManager: any ErrorManagerProtocol
        let fileSystemService: FileSystemService
        let fileEditorService: (any FileEditorServiceProtocol)?
        let activityCoordinator: (any AgentActivityCoordinating)?
    }

    struct EnvironmentDependencies {
        let workspaceService: any WorkspaceServiceProtocol
        let eventBus: any EventBusProtocol
        let projectRoot: URL?
        let codebaseIndex: CodebaseIndexProtocol?
    }

    private struct UserMessageContext {
        let text: String
        let mediaAttachments: [ChatMessageMediaAttachment]
        let hasSelectionContext: Bool
        let message: ChatMessage
    }

    // MARK: - Published State

    @Published var currentInput: String = ""
    @Published var currentMediaAttachments: [ChatMessageMediaAttachment] = []
    @Published var isSending: Bool = false
    @Published var error: String?
    @Published var currentMode: AIMode = .chat
    @Published var cancelledToolCallIds: Set<String> = []
    @Published private(set) var liveModelOutputPreview: String = ""
    @Published private(set) var liveModelOutputStatusPreview: String = ""
    @Published private(set) var isLiveModelOutputPreviewVisible: Bool = true
    @Published private(set) var conversationTabs: [ConversationTabItem] = []
    @Published private(set) var providerIssue: ConversationProviderIssueState?
    @Published private(set) var messages: [ChatMessage] = []

    /// Tooling stack (reserved for future use)

    // MARK: - Dependencies

    private let historyCoordinator: ChatHistoryCoordinator
    private let toolExecutor: AIToolExecutor
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private var aiService: AIService
    private let aiInteractionCoordinator: AIInteractionCoordinator
    private let sendCoordinator: ConversationSendCoordinator
    private let errorManager: any ErrorManagerProtocol
    private let fileSystemService: FileSystemService
    private weak var fileEditorService: (any FileEditorServiceProtocol)?
    private let workspaceService: any WorkspaceServiceProtocol
    private let eventBus: any EventBusProtocol
    private var codebaseIndex: (any CodebaseIndexProtocol)?
    private var projectRoot: URL
    private var vectorStoreService: VectorStoreService?
    private let conversationLogger: ConversationLogger
    private let settingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)
    private lazy var aiRouter = AIRouter(settingsStore: settingsStore)
    private let sessionManager: SessionManager
    private let activityCoordinator: AgentActivityCoordinating?
    /// Token for the current API sending activity
    private var apiSendingActivityToken: AgentActivityToken?
    private lazy var toolProvider = ConversationToolProvider(
        fileSystemService: fileSystemService,
        eventBus: eventBus,
        vectorStoreService: nil,
        embedder: nil,
        aiServiceProvider: { [weak self] in self?.aiService },
        codebaseIndexProvider: { [weak self] in self?.codebaseIndex },
        projectRootProvider: { [weak self] in self?.projectRoot }
    )
    private var cancellables = Set<AnyCancellable>()

    private var activeStreamingRunId: String?
    private var draftAssistantMessageId: UUID?
    private var draftAssistantText: String = ""
    private var draftReasoningText: String = ""
    private var streamingRenderTask: Task<Void, Never>?
    private var lastRenderedDraftContent: String = ""
    private var lastRenderedDraftReasoning: String = ""
    private let outputBuffer = StreamingOutputBuffer()
    private var activeSendTask: Task<Void, Never>?
    private let maxPreviewCharacters = 12_000
    private let maxStatusPreviewCharacters = 4_000

    // Coalesced live preview support
    private var pendingPreviewBuffer: String = ""
    private var previewPublishTask: Task<Void, Never>?
    private let previewCoalesceIntervalNanoseconds: UInt64 = 30_000_000

    // MARK: - Computed Properties

    var currentConversationId: String {
        sessionManager.selectedId
    }

    private var conversationId: String {
        sessionManager.selectedId
    }

    private var pathValidator: PathValidator {
        workspaceService.makePathValidator(projectRoot: projectRoot)
    }

    private var availableTools: [AITool] {
        toolProvider.availableTools(mode: currentMode, pathValidator: pathValidator)
    }

    // MARK: - Initialization

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

        self.historyCoordinator = ChatHistoryCoordinator()
        let currentModel = OpenRouterSettingsStore().load().model
        self.historyCoordinator.updateStrategy(forModel: currentModel)
        self.sessionManager = SessionManager(
            historyCoordinator: historyCoordinator,
            projectRoot: root
        )
        let fileEditorServiceProvider = fileEditorService
        self.toolExecutor = AIToolExecutor(
            fileSystemService: dependencies.services.fileSystemService,
            errorManager: dependencies.services.errorManager,
            projectRoot: root,
            eventBus: dependencies.environment.eventBus,
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

        // Wire up streaming reset after all properties are initialized
        self.sendCoordinator.clearStreamingBuffer = { [weak self] in
            self?.clearStreamingText()
        }

        initializeLogging(root: root)
        setupObservation()
        setupPowerManagementObservation()
        setupStreamingSubscriptions()
        observeSessionTabs()
        observeHistoryMessages()
        startTraceLogging()
        configureLoggingStores(root: root)
    }

    deinit {
        activeSendTask?.cancel()
        streamingRenderTask?.cancel()
    }

    // MARK: - Session Management

    private func observeSessionTabs() {
        sessionManager.$conversationTabs
            .sink { [weak self] tabs in
                self?.conversationTabs = tabs
            }
            .store(in: &cancellables)
    }

    private func observeHistoryMessages() {
        historyCoordinator.$messages
            .sink { [weak self] msgs in
                self?.messages = msgs
            }
            .store(in: &cancellables)
    }

    private func saveCurrentSessionSnapshot() {
        sessionManager.saveSnapshot(
            input: currentInput,
            livePreview: liveModelOutputPreview,
            liveStatusPreview: liveModelOutputStatusPreview,
            mode: currentMode
        )
    }

    private func restoreSession(_ sessionId: String) {
        cancelledToolCallIds.removeAll()
        sessionManager.restoreSession(
            sessionId,
            input: &currentInput,
            livePreview: &liveModelOutputPreview,
            liveStatusPreview: &liveModelOutputStatusPreview,
            mode: &currentMode
        )
    }

    // MARK: - Event Bus Subscriptions

    private func setupStreamingSubscriptions() {
        eventBus
            .subscribe(to: LocalModelStreamingChunkEvent.self) { [weak self] event in
                guard let self else { return }
                self.handleLocalModelStreamingChunk(event)
            }
            .store(in: &cancellables)

        eventBus
            .subscribe(to: LocalModelStreamingReasoningChunkEvent.self) { [weak self] event in
                guard let self else { return }
                self.handleLocalModelStreamingReasoningChunk(event)
            }
            .store(in: &cancellables)

        eventBus
            .subscribe(to: LocalModelStreamingStatusEvent.self) { [weak self] event in
                guard let self else { return }
                self.handleLocalModelStreamingStatus(event)
            }
            .store(in: &cancellables)

        eventBus
            .subscribe(to: ProviderIssueStatusEvent.self) { [weak self] event in
                guard let self else { return }
                if event.statusKind == .resolved {
                    self.providerIssue = nil
                    return
                }
                self.providerIssue = ConversationProviderIssueState(
                    providerName: event.providerName,
                    issueType: self.providerIssueTypeLabel(for: event.statusKind),
                    statusCode: event.statusCode,
                    message: event.message,
                    cooldownUntil: event.cooldownUntil
                )
            }
            .store(in: &cancellables)

        eventBus
            .subscribe(to: OpenRouterUsageUpdatedEvent.self) { [weak self] event in
                guard let self else { return }
                self.handleOpenRouterUsageUpdated(event)
            }
            .store(in: &cancellables)
    }

    // MARK: - Provider Helpers

    private func providerIssueTypeLabel(for statusKind: ProviderIssueStatusEvent.StatusKind) -> String {
        switch statusKind {
        case .resolved:
            return "Resolved"
        case .rateLimited:
            return "Rate limit"
        case .unavailable:
            return "Provider unavailable"
        case .authentication:
            return "Authentication"
        case .transport:
            return "Connection"
        case .networkOffline:
            return "Network offline"
        case .insufficientBalance:
            return "Insufficient balance"
        case .unknown:
            return "Provider issue"
        }
    }

    // MARK: - Streaming Rendering

    private func handleLocalModelStreamingChunk(_ event: LocalModelStreamingChunkEvent) {
        guard let runId = activeStreamingRunId, runId == event.runId else { return }
        guard let draftId = draftAssistantMessageId else { return }
        guard !event.chunk.isEmpty else { return }

        appendToLiveModelPreview(event.chunk)
        renderStreamingChunk(event.chunk, draftId: draftId)
    }

    private func handleLocalModelStreamingReasoningChunk(_ event: LocalModelStreamingReasoningChunkEvent) {
        guard let runId = activeStreamingRunId, runId == event.runId else { return }
        guard let draftId = draftAssistantMessageId else { return }
        guard !event.chunk.isEmpty else { return }

        renderStreamingReasoning(event.chunk, draftId: draftId)
    }

    private func renderStreamingChunk(_ chunk: String, draftId: UUID) {
        draftAssistantText.append(chunk)
        outputBuffer.appendContent(chunk)
        let renderContent = outputBuffer.hasContent ? outputBuffer.content : ""
        guard renderContent != lastRenderedDraftContent else { return }
        lastRenderedDraftContent = renderContent
        let renderReasoning: String? = outputBuffer.hasReasoning ? outputBuffer.reasoning : nil
        historyCoordinator.setDraft(
            ChatMessage(
                id: draftId,
                role: .assistant,
                content: renderContent,
                timestamp: historyCoordinator.getDraftMessage(id: draftId)?.timestamp ?? Date(),
                context: ChatMessageContentContext(reasoning: renderReasoning),
                isDraft: true
            )
        )
    }

    private func renderStreamingReasoning(_ chunk: String, draftId: UUID) {
        draftReasoningText.append(chunk)
        outputBuffer.appendReasoning(chunk)
        let renderReasoning: String? = outputBuffer.hasReasoning ? outputBuffer.reasoning : nil
        guard renderReasoning != lastRenderedDraftReasoning else { return }
        lastRenderedDraftReasoning = renderReasoning ?? ""
        let renderContent = outputBuffer.hasContent ? outputBuffer.content : ""
        historyCoordinator.setDraft(
            ChatMessage(
                id: draftId,
                role: .assistant,
                content: renderContent,
                timestamp: historyCoordinator.getDraftMessage(id: draftId)?.timestamp ?? Date(),
                context: ChatMessageContentContext(reasoning: renderReasoning),
                isDraft: true
            )
        )
    }

    private func handleLocalModelStreamingStatus(_ event: LocalModelStreamingStatusEvent) {
        guard let runId = activeStreamingRunId, runId == event.runId else { return }
        appendToLiveModelStatusPreview(event.message)
    }

    private func handleOpenRouterUsageUpdated(_ event: OpenRouterUsageUpdatedEvent) {
        guard let runId = event.runId, runId == activeStreamingRunId else { return }
        guard let draftId = draftAssistantMessageId else { return }
        guard let draftMessage = historyCoordinator.getDraftMessage(id: draftId) else { return }

        historyCoordinator.setDraft(
            ChatMessage(
                id: draftMessage.id,
                role: draftMessage.role,
                content: draftMessage.content,
                mediaAttachments: draftMessage.mediaAttachments,
                timestamp: draftMessage.timestamp,
                context: ChatMessageContentContext(
                    reasoning: draftMessage.reasoning,
                    codeContext: draftMessage.codeContext
                ),
                billing: ChatMessageBillingContext(
                    requestCostMicrodollars: event.usage.costMicrodollars,
                    providerName: event.providerName,
                    modelId: event.modelId,
                    runId: event.runId
                ),
                tool: ChatMessageToolContext(
                    toolName: draftMessage.toolName,
                    toolStatus: draftMessage.toolStatus,
                    target: ToolInvocationTarget(
                        targetFile: draftMessage.targetFile,
                        toolCallId: draftMessage.toolCallId
                    ),
                    toolCalls: draftMessage.toolCalls ?? []
                ),
                isDraft: draftMessage.isDraft
            )
        )
    }

    // MARK: - Observation

    private func setupObservation() {
        historyCoordinator.objectWillChange
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
        conversationLogger.initializeProjectRoot(root, eventBus: eventBus)
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

    // MARK: - Dependency Updates

    func updateAIService(_ newService: AIService) {
        self.aiService = newService
        aiInteractionCoordinator.updateAIService(newService)
    }

    func updateCodebaseIndex(_ newIndex: CodebaseIndexProtocol?) {
        codebaseIndex = newIndex
        aiInteractionCoordinator.updateCodebaseIndex(newIndex)
    }

    func updateVectorStoreService(_ service: VectorStoreService?) {
        vectorStoreService = service
        aiInteractionCoordinator.updateVectorStoreService(service)
    }

    func updateEmbedder(_ embedder: (any MemoryEmbeddingGenerating)?) {
        aiInteractionCoordinator.updateEmbedder(embedder)
    }

    func updateProjectRoot(_ newRoot: URL) {
        if projectRoot.standardizedFileURL == newRoot.standardizedFileURL {
            return
        }

        projectRoot = newRoot
        toolExecutor.updateProjectRoot(newRoot)
        configureLoggingStores(root: newRoot)

        saveCurrentSessionSnapshot()

        clearConversation()

        historyCoordinator.updateProjectRoot(
            newRoot,
            shouldStartConversationLog: true,
            onStartConversation: { _, _, _ in
                _ = ()
            }
        )

        sessionManager.updateProjectRoot(
            newRoot,
            input: &currentInput,
            livePreview: &liveModelOutputPreview,
            liveStatusPreview: &liveModelOutputStatusPreview,
            mode: &currentMode
        )

        conversationLogger.initializeProjectRoot(newRoot, eventBus: eventBus)
        startTraceLogging()
        conversationLogger.logConversationStart(
            conversationId: self.conversationId,
            mode: self.currentMode.rawValue,
            projectRootPath: newRoot.path
        )
    }

    // MARK: - Send Pipeline

    func sendMessage() {
        sendMessage(context: nil)
    }

    func sendMessage(context: String? = nil) {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userContext = buildUserMessageContext(context: context)
        logUserMessage(userContext)
        historyCoordinator.append(userContext.message)
        if historyCoordinator.conversationEnvelope.subject.isEmpty {
            let preview = String(userContext.message.content.prefix(60))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !preview.isEmpty {
                historyCoordinator.updateSubject(preview)
                sessionManager.saveSnapshot(input: currentInput, livePreview: liveModelOutputPreview, liveStatusPreview: liveModelOutputStatusPreview, mode: currentMode)
            }
        }
        publishContextEvent()
        resetInputState()
        startSendTask(userContext: userContext, explicitContext: context)
    }

    private func buildUserMessageContext(context: String?) -> UserMessageContext {
        let userMessageText = currentInput
        let mediaAttachments = currentMediaAttachments
        let hasSelectionContext = (context?.isEmpty == false)
        let userMessage = ChatMessage(
            role: .user,
            content: currentInput,
            mediaAttachments: mediaAttachments,
            context: ChatMessageContentContext(codeContext: context)
        )
        return UserMessageContext(
            text: userMessageText,
            mediaAttachments: mediaAttachments,
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
        currentMediaAttachments = []
        isSending = true
        error = nil
        providerIssue = nil
    }

    private func publishContextEvent() {
        let msgs = historyCoordinator.messages
        let totalChars = msgs.reduce(0) { $0 + $1.content.count }
        // Only enforce context window for local models (slider in settings).
        // Remote APIs manage their own context limits; we just report usage.
        let isOffline = aiRouter.usesLocalModel
        let contextTokens = settingsStore.integer(forKey: "LocalModel.ContextLength")
        let contextWindowChars: Int? = (isOffline && contextTokens > 0) ? contextTokens * 4 : nil
        let kvCache4BitEnabled = settingsStore.bool(forKey: "LocalModel.KVCache4BitEnabled", default: false)
        let compressionRatio: Double? = (isOffline && kvCache4BitEnabled) ? 8.0 : nil
        eventBus.publish(ConversationContextEvent(
            totalCharCount: totalChars,
            messageCount: msgs.count,
            contextWindowChars: contextWindowChars,
            compressionRatio: compressionRatio
        ))
    }

    // MARK: - Preview Helpers

    private func appendToLiveModelPreview(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        pendingPreviewBuffer.append(chunk)
        schedulePreviewPublish()
    }

    private func schedulePreviewPublish() {
        guard previewPublishTask == nil else { return }
        previewPublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: self.previewCoalesceIntervalNanoseconds) } catch { return }
            guard !Task.isCancelled else { return }
            self.flushPendingPreview()
        }
    }

    private func flushPendingPreview() {
        previewPublishTask = nil
        guard !pendingPreviewBuffer.isEmpty else { return }
        liveModelOutputPreview.append(pendingPreviewBuffer)
        pendingPreviewBuffer = ""
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

    // MARK: - State Reset

    private func resetStreamingDraftState() {
        activeStreamingRunId = nil
        draftAssistantMessageId = nil
        draftAssistantText = ""
        draftReasoningText = ""
        lastRenderedDraftContent = ""
        lastRenderedDraftReasoning = ""
        outputBuffer.clear()
        previewPublishTask?.cancel()
        previewPublishTask = nil
        pendingPreviewBuffer = ""
        streamingRenderTask?.cancel()
        streamingRenderTask = nil
    }

    /// Resets the streaming text buffer without clearing run state.
    /// Used when the local model tool loop needs to start fresh output.
    @MainActor
    func clearStreamingText() {
        draftAssistantText = ""
        draftReasoningText = ""
        lastRenderedDraftContent = ""
        lastRenderedDraftReasoning = ""
        outputBuffer.clear()
    }

    private func resetConversationInteractionState() {
        resetStreamingDraftState()
        isSending = false
        error = nil
        providerIssue = nil
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

            let tools = self.currentMode.allowedTools(from: self.availableTools)

            do {
                conversationLogger.logAIRequestStart(
                    mode: self.currentMode.rawValue,
                    historyCount: self.messages.count
                )

                if self.currentMode == .coder {
                    // Coder mode uses the PROVEN ToolLoopHandler (same as Agent mode)
                    // but with tools filtered to exclude replace_in_file.
                    // The AIMode.allowedTools(from:) handles this filtering.
                    self.setLiveModelStatusPreview("Coder mode: using proven Agent tool chain with Coder toolset…")
                    try await self.sendCoordinator.send(
                        SendRequest(
                            userInput: userContext.text,
                            mediaAttachments: userContext.mediaAttachments,
                            mode: self.currentMode,
                            projectRoot: self.projectRoot,
                            conversationId: self.conversationId,
                            runId: runId,
                            availableTools: tools,
                            cancelledToolCallIds: { [cancelledIds = self.cancelledToolCallIds] in cancelledIds },
                            qaReviewEnabled: false,
                            draftAssistantMessageId: self.draftAssistantMessageId,
                            usesLocalModel: self.aiRouter.usesLocalModel
                        )
                    )
                } else {
                    // Legacy Agent/Chat mode — uses existing ToolLoopHandler
                    try await self.sendCoordinator.send(
                        SendRequest(
                            userInput: userContext.text,
                            mediaAttachments: userContext.mediaAttachments,
                            mode: self.currentMode,
                            projectRoot: self.projectRoot,
                            conversationId: self.conversationId,
                            runId: runId,
                            availableTools: tools,
                            cancelledToolCallIds: { [cancelledIds = self.cancelledToolCallIds] in cancelledIds },
                            qaReviewEnabled: self.currentMode == .agent && self.settingsStore.bool(forKey: AppConstantsStorage.agentQAReviewEnabledKey, default: false),
                            draftAssistantMessageId: self.draftAssistantMessageId,
                            usesLocalModel: self.aiRouter.usesLocalModel
                        )
                    )
                }

                                self.flushPendingPreview()
                if let finalAssistantMessage = self.messages.last(where: { $0.role == .assistant && !$0.isDraft }) {
                    self.setLiveModelPreview(finalAssistantMessage.content)
                }
                self.appendToLiveModelStatusPreview("Run completed.")
                self.resetStreamingDraftState()
                self.providerIssue = nil
                self.isSending = false
                self.eventBus.publish(ConversationRunCompletedEvent(runId: runId))
            } catch {
                // Clean up draft message on error
                if let draftId = self.draftAssistantMessageId {
                    self.historyCoordinator.clearDraft()
                }
                self.resetStreamingDraftState()
                if error is CancellationError || Task.isCancelled || self.isLikelyCancellation(error) {
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

    private func isLikelyCancellation(_ error: Error) -> Bool {
        let normalized = String(describing: error).lowercased()
        return normalized.contains("cancellationerror")
            || normalized.contains("request cancelled")
            || normalized.contains("request canceled")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
    }

    // MARK: - Conversation Lifecycle

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
        historyCoordinator.clearConversation()

        let oldConversationId = sessionManager.selectedId
        let newConversationId = sessionManager.startNew(
            input: &currentInput,
            livePreview: &liveModelOutputPreview,
            liveStatusPreview: &liveModelOutputStatusPreview,
            mode: &currentMode
        )
        cancelledToolCallIds.removeAll()

        conversationLogger.logConversationStart(
            conversationId: newConversationId,
            mode: self.currentMode.rawValue,
            projectRootPath: self.projectRoot.path,
            previousConversationId: oldConversationId
        )
    }

    func switchConversation(to id: String) {
        cancelActiveSendTask()
        resetConversationInteractionState()
        saveCurrentSessionSnapshot()
        guard sessionManager.switchTo(
            id: id,
            input: &currentInput,
            livePreview: &liveModelOutputPreview,
            liveStatusPreview: &liveModelOutputStatusPreview,
            mode: &currentMode
        ) else { return }
    }

    func closeConversation(id: String) {
        cancelActiveSendTask()
        saveCurrentSessionSnapshot()
        _ = sessionManager.close(
            id: id,
            input: &currentInput,
            livePreview: &liveModelOutputPreview,
            liveStatusPreview: &liveModelOutputStatusPreview,
            mode: &currentMode
        )
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
        historyCoordinator.cancelLiveTool(toolCallId: id, content: "Cancelled by user")
    }

    // MARK: - Quick Actions

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
                self.historyCoordinator.append(
                    ChatMessage(
                        role: .user,
                        content: "Explain this code",
                        context: ChatMessageContentContext(codeContext: code)
                    )
                )
                self.historyCoordinator.append(ChatMessage(role: .assistant, content: response))
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
                self.historyCoordinator.append(
                    ChatMessage(
                        role: .user,
                        content: "Refactor this code: \(instructions)",
                        context: ChatMessageContentContext(codeContext: code)
                    )
                )
                self.historyCoordinator.append(
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
