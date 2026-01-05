//
//  ConversationManager.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Combine

@MainActor
class ConversationManager: ObservableObject, ConversationManagerProtocol {
    @Published var currentInput: String = ""
    @Published var isSending: Bool = false
    @Published var error: String? = nil
    @Published var currentMode: AIMode = .chat
    @Published var cancelledToolCallIds: Set<String> = []
    
    private let conversationId: String
    
    private let historyManager: ChatHistoryManager
    private let toolExecutor: AIToolExecutor
    private var aiService: AIService
    private let errorManager: ErrorManagerProtocol
    private let fileSystemService: FileSystemService
    private var codebaseIndex: CodebaseIndexProtocol?
    private var projectRoot: URL
    private var cancellables = Set<AnyCancellable>()
    
    var messages: [ChatMessage] {
        historyManager.messages
    }

    private var pathValidator: PathValidator {
        return PathValidator(projectRoot: projectRoot)
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

        tools.append(WriteFileTool(fileSystemService: fileSystemService, pathValidator: validator))
        tools.append(WriteFilesTool(fileSystemService: fileSystemService, pathValidator: validator))
        tools.append(CreateFileTool(pathValidator: validator))
        tools.append(DeleteFileTool(pathValidator: validator))
        tools.append(ReplaceInFileTool(fileSystemService: fileSystemService, pathValidator: validator))
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: validator))

        tools.append(ArchitectAdvisorTool(aiService: aiService, index: codebaseIndex, projectRoot: projectRoot))
        tools.append(PlannerTool())

        return tools
    }
    
    private var availableTools: [AITool] {
        return currentMode.allowedTools(from: allTools)
    }
    
    init(aiService: AIService, errorManager: ErrorManagerProtocol, fileSystemService: FileSystemService = FileSystemService(), projectRoot: URL? = nil, codebaseIndex: CodebaseIndexProtocol? = nil) {
        self.conversationId = UUID().uuidString
        self.aiService = aiService
        self.errorManager = errorManager
        self.fileSystemService = fileSystemService
        let root = projectRoot ?? FileManager.default.temporaryDirectory
        self.projectRoot = root
        self.codebaseIndex = codebaseIndex
        
        self.historyManager = ChatHistoryManager()
        self.historyManager.setProjectRoot(root)
        self.toolExecutor = AIToolExecutor(fileSystemService: fileSystemService, errorManager: errorManager, projectRoot: root)

        setupObservation()
        
        Task {
            let logPath = await AIToolTraceLogger.shared.currentLogFilePath()
            await AIToolTraceLogger.shared.log(type: "trace.start", data: [
                "logFile": logPath,
                "mode": self.currentMode.rawValue,
                "projectRoot": self.projectRoot.path
            ])
        }

        Task {
            await AppLogger.shared.info(category: .conversation, message: "conversation.start", metadata: [
                "conversationId": self.conversationId,
                "mode": self.currentMode.rawValue,
                "projectRoot": self.projectRoot.path
            ])
            await ConversationLogStore.shared.append(
                conversationId: self.conversationId,
                type: "conversation.start",
                data: [
                    "mode": self.currentMode.rawValue,
                    "projectRoot": self.projectRoot.path
                ]
            )

            await ConversationIndexStore.shared.appendStart(
                conversationId: self.conversationId,
                mode: self.currentMode.rawValue,
                projectRootPath: self.projectRoot.path
            )
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
        projectRoot = newRoot

        historyManager.setProjectRoot(newRoot)

        Task {
            await AppLogger.shared.setProjectRoot(newRoot)
            await ConversationLogStore.shared.setProjectRoot(newRoot)
            await ConversationIndexStore.shared.setProjectRoot(newRoot)
            await ConversationPlanStore.shared.setProjectRoot(newRoot)
            await AppLogger.shared.info(category: .app, message: "logging.project_root_set", metadata: [
                "projectRoot": newRoot.path
            ])
        }
    }
    
    func sendMessage() {
        sendMessage(context: nil)
    }

    func sendMessage(context: String? = nil) {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task {
            await AIToolTraceLogger.shared.log(type: "chat.user_message", data: [
                "mode": currentMode.rawValue,
                "projectRoot": projectRoot.path,
                "inputLength": currentInput.count,
                "hasSelectionContext": (context?.isEmpty == false)
            ])

            await AppLogger.shared.info(category: .conversation, message: "chat.user_message", metadata: [
                "conversationId": self.conversationId,
                "mode": self.currentMode.rawValue,
                "projectRoot": self.projectRoot.path,
                "inputLength": self.currentInput.count,
                "hasSelectionContext": (context?.isEmpty == false)
            ])
            await ConversationLogStore.shared.append(
                conversationId: self.conversationId,
                type: "chat.user_message",
                data: [
                    "content": self.currentInput,
                    "hasSelectionContext": (context?.isEmpty == false)
                ]
            )
        }
        
        let userMessage = ChatMessage(role: .user, content: currentInput, codeContext: context)
        historyManager.append(userMessage)
        
        currentInput = ""
        isSending = true
        error = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                await AIToolTraceLogger.shared.log(type: "chat.ai_request_start", data: [
                    "mode": self.currentMode.rawValue,
                    "projectRoot": self.projectRoot.path,
                    "historyCount": self.messages.count
                ])

                await AppLogger.shared.info(category: .ai, message: "chat.ai_request_start", metadata: [
                    "conversationId": self.conversationId,
                    "mode": self.currentMode.rawValue,
                    "projectRoot": self.projectRoot.path,
                    "historyCount": self.messages.count
                ])
                await ConversationLogStore.shared.append(
                    conversationId: self.conversationId,
                    type: "chat.ai_request_start",
                    data: [
                        "mode": self.currentMode.rawValue,
                        "historyCount": self.messages.count
                    ]
                )

                var currentResponse = try await sendMessageWithRetry(
                    messages: self.messages,
                    context: context,
                    tools: availableTools,
                    mode: currentMode,
                    projectRoot: projectRoot
                )

                if currentMode == .agent,
                   (currentResponse.toolCalls?.isEmpty ?? true),
                   let content = currentResponse.content,
                   ChatPromptBuilder.shouldForceToolFollowup(content: content),
                   let lastUserMessage = self.messages.last(where: { $0.role == .user }) {
                    
                    let followupSystem = ChatMessage(
                        role: .system,
                        content: "You indicated you will implement changes, but you returned no tool calls. In Agent mode, you MUST now proceed by calling the appropriate tools. Return tool calls now."
                    )

                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [followupSystem, lastUserMessage],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                }
                
                var toolIteration = 0
                let maxIterations = (currentMode == .agent) ? 12 : 5
                
                while let toolCalls = currentResponse.toolCalls, !toolCalls.isEmpty && toolIteration < maxIterations {
                    toolIteration += 1

                    let split = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "")
                    let assistantMsg = ChatMessage(
                        role: .assistant,
                        content: split.content,
                        reasoning: split.reasoning,
                        toolCalls: toolCalls
                    )
                    historyManager.append(assistantMsg)

                    await AppLogger.shared.info(category: .conversation, message: "chat.assistant_tool_calls", metadata: [
                        "conversationId": self.conversationId,
                        "toolCalls": toolCalls.count
                    ])
                    await ConversationLogStore.shared.append(
                        conversationId: self.conversationId,
                        type: "chat.assistant_tool_calls",
                        data: [
                            "content": split.content,
                            "toolCalls": toolCalls.map { [
                                "id": $0.id,
                                "name": $0.name
                            ] }
                        ]
                    )
                    
                    let _ = await toolExecutor.executeBatch(toolCalls, availableTools: availableTools, conversationId: self.conversationId) { progressMsg in
                        self.historyManager.append(progressMsg)
                    }
                    
                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages,
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                }

                if ChatPromptBuilder.needsReasoningFormatCorrection(text: currentResponse.content ?? "") {
                    let correctionSystem = ChatMessage(
                        role: .system,
                        content: "Your <ide_reasoning> block must include ALL four sections: Analyze, Research, Plan, Reflect."
                    )
                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [correctionSystem],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                }

                if ChatPromptBuilder.isLowQualityReasoning(text: currentResponse.content ?? "") {
                    let correctionSystem = ChatMessage(
                        role: .system,
                        content: "Your <ide_reasoning> block is too vague (placeholders like '...' are not allowed). Provide concise, concrete bullet points for EACH section: Analyze, Research, Plan, Reflect. If unknown, write 'N/A' and state what information is needed."
                    )
                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [correctionSystem],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )
                }

                let splitFinal = ChatPromptBuilder.splitReasoning(from: currentResponse.content ?? "No response received.")
                historyManager.append(ChatMessage(role: .assistant, content: splitFinal.content, reasoning: splitFinal.reasoning))

                let hasReasoning = (splitFinal.reasoning?.isEmpty == false)

                await AppLogger.shared.info(category: .conversation, message: "chat.assistant_message", metadata: [
                    "conversationId": self.conversationId,
                    "contentLength": splitFinal.content.count,
                    "hasReasoning": hasReasoning
                ])
                await ConversationLogStore.shared.append(
                    conversationId: self.conversationId,
                    type: "chat.assistant_message",
                    data: [
                        "content": splitFinal.content,
                        "reasoning": splitFinal.reasoning
                    ]
                )
                isSending = false
                
            } catch {
                Task {
                    await AppLogger.shared.error(category: .error, message: "chat.error", metadata: [
                        "conversationId": self.conversationId,
                        "error": error.localizedDescription
                    ])
                    await ConversationLogStore.shared.append(
                        conversationId: self.conversationId,
                        type: "chat.error",
                        data: [
                            "error": error.localizedDescription
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
    ) async throws -> AIServiceResponse {
        let maxAttempts = 3
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let augmentedContext = ContextBuilder.buildContext(
                    userInput: messages.last(where: { $0.role == .user })?.content ?? "",
                    explicitContext: context,
                    index: codebaseIndex,
                    projectRoot: projectRoot
                )
                return try await aiService.sendMessage(messages, context: augmentedContext, tools: tools, mode: mode, projectRoot: projectRoot)
            } catch {
                lastError = error
                if attempt < maxAttempts { try await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
        throw lastError ?? NSError(domain: "ConversationManager", code: -1)
    }
    
    func clearConversation() {
        historyManager.clear()
        cancelledToolCallIds.removeAll()
    }
    
    func cancelToolCall(id: String) {
        cancelledToolCallIds.insert(id)
        // Find the specific tool execution message and mark it as failed/cancelled
        historyManager.updateMessageStatus(toolCallId: id, status: .failed, content: "Cancelled by user")
    }
    
    func explainCode(_ code: String) {
        isSending = true
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await aiService.explainCode(code)
                self.historyManager.append(ChatMessage(role: .user, content: "Explain this code", codeContext: code))
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
                self.historyManager.append(ChatMessage(role: .user, content: "Refactor this code: \(instructions)", codeContext: code))
                self.historyManager.append(ChatMessage(role: .assistant, content: "Here's the refactored code:", codeContext: response))
                self.isSending = false
            } catch {
                self.error = "Failed to refactor code: \(error.localizedDescription)"
                self.isSending = false
            }
        }
    }
}