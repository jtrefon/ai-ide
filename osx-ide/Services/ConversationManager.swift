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
    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isSending: Bool = false
    @Published var error: String? = nil
    @Published var currentMode: AIMode = .chat
    
    private var aiService: AIService
    private let errorManager: ErrorManagerProtocol
    private let fileSystemService: FileSystemService
    private var codebaseIndex: CodebaseIndexProtocol?
    private let historyKey = "AIChatHistory"
    private var cancellables = Set<AnyCancellable>()
    
    // Project root for sandboxing
    var projectRoot: URL
    
    private var pathValidator: PathValidator {
        return PathValidator(projectRoot: projectRoot)
    }
    
    private var allTools: [AITool] {
        let validator = pathValidator

        var tools: [AITool] = []

        // Index-backed discovery & search tools (preferred, authoritative).
        if let codebaseIndex {
            tools.append(IndexFindFilesTool(index: codebaseIndex))
            tools.append(IndexListFilesTool(index: codebaseIndex))
            tools.append(IndexSearchTextTool(index: codebaseIndex))
            tools.append(IndexReadFileTool(index: codebaseIndex))
            tools.append(IndexSearchSymbolsTool(index: codebaseIndex))
        }

        // File operations (writing/editing still uses the filesystem, but discovery/search should use the index).
        tools.append(WriteFileTool(fileSystemService: fileSystemService, pathValidator: validator))
        tools.append(WriteFilesTool(fileSystemService: fileSystemService, pathValidator: validator))
        tools.append(CreateFileTool(pathValidator: validator))
        tools.append(DeleteFileTool(pathValidator: validator))
        tools.append(ReplaceInFileTool(fileSystemService: fileSystemService, pathValidator: validator))

        // Execution
        tools.append(RunCommandTool(projectRoot: projectRoot, pathValidator: validator))

        return tools
    }
    
    private var availableTools: [AITool] {
        return currentMode.allowedTools(from: allTools)
    }
    
    init(aiService: AIService, errorManager: ErrorManagerProtocol, fileSystemService: FileSystemService = FileSystemService(), projectRoot: URL? = nil, codebaseIndex: CodebaseIndexProtocol? = nil) {
        self.aiService = aiService
        self.errorManager = errorManager
        self.fileSystemService = fileSystemService
        self.projectRoot = projectRoot ?? FileManager.default.temporaryDirectory
        self.codebaseIndex = codebaseIndex
        loadConversationHistory()

        Task {
            let logPath = await AIToolTraceLogger.shared.currentLogFilePath()
            await AIToolTraceLogger.shared.log(type: "trace.start", data: [
                "logFile": logPath,
                "mode": self.currentMode.rawValue,
                "projectRoot": self.projectRoot.path
            ])
        }
        
        // If no messages, initialize with a welcome message
        if messages.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI coding assistant. How can I help you today?"
            ))
        }
    }
    
    /// Update the AI service (used by dependency container)
    func updateAIService(_ newService: AIService) {
        self.aiService = newService
    }

    func updateCodebaseIndex(_ newIndex: CodebaseIndexProtocol?) {
        self.codebaseIndex = newIndex
    }
    
    func updateProjectRoot(_ newRoot: URL) {
        projectRoot = newRoot
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
        }
        
        // Add user message to conversation
        let userMessage = ChatMessage(
            role: .user,
            content: currentInput,
            codeContext: context
        )
        messages.append(userMessage)
        
        // Clear input and set sending state
        let userInput = currentInput
        currentInput = ""
        isSending = true
        error = nil
        
        // Save conversation history
        saveConversationHistory()
        
        // Get AI response using the AI service
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                await AIToolTraceLogger.shared.log(type: "chat.ai_request_start", data: [
                    "mode": self.currentMode.rawValue,
                    "projectRoot": self.projectRoot.path,
                    "historyCount": self.messages.count
                ])
                // Initial call with full history
                var currentResponse = try await sendMessageWithRetry(
                    messages: self.messages,
                    context: context,
                    tools: availableTools,
                    mode: currentMode,
                    projectRoot: projectRoot
                )

                await AIToolTraceLogger.shared.log(type: "chat.ai_response", data: [
                    "contentLength": currentResponse.content?.count ?? 0,
                    "toolCalls": currentResponse.toolCalls?.count ?? 0
                ])

                if currentMode == .agent,
                   (currentResponse.toolCalls?.isEmpty ?? true),
                   let content = currentResponse.content,
                   Self.shouldForceToolFollowup(content: content),
                   let lastUserMessage = self.messages.last(where: { $0.role == .user }) {
                    await AIToolTraceLogger.shared.log(type: "agent.tool_followup.trigger", data: [
                        "contentLength": content.count
                    ])

                    let followupSystem = ChatMessage(
                        role: .system,
                        content: "You indicated you will implement changes, but you returned no tool calls. In Agent mode, you MUST now proceed by calling the appropriate tools (index_search_text/index_search_symbols/index_list_files/index_read_file/replace_in_file/write_file/run_command) to make the changes. Return tool calls now. If you cannot, explicitly state the blocker."
                    )

                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages + [followupSystem, lastUserMessage],
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )

                    await AIToolTraceLogger.shared.log(type: "agent.tool_followup.response", data: [
                        "contentLength": currentResponse.content?.count ?? 0,
                        "toolCalls": currentResponse.toolCalls?.count ?? 0
                    ])
                }
                
                // Tool calling loop
                var toolIteration = 0
                let maxIterations = (currentMode == .agent) ? 12 : 5
                var toolCallSignatureCounts: [String: Int] = [:]
                let maxRepeatsPerSignature = 2
                
                // Check if response has tool calls
                while let toolCalls = currentResponse.toolCalls, !toolCalls.isEmpty && toolIteration < maxIterations {
                    toolIteration += 1

                    await AIToolTraceLogger.shared.log(type: "tool.loop_start", data: [
                        "iteration": toolIteration,
                        "toolCalls": toolCalls.count
                    ])

                    var tempSignatureCounts = toolCallSignatureCounts
                    var abortRepeatedTool: (name: String, id: String, nextCount: Int)?

                    for toolCall in toolCalls {
                        let signature: String = {
                            let args = toolCall.arguments
                                .map { (key: $0.key, value: String(describing: $0.value)) }
                                .sorted { $0.key < $1.key }
                                .map { "\($0.key)=\($0.value)" }
                                .joined(separator: ",")
                            return "\(toolCall.name)|\(args)"
                        }()

                        let nextCount = (tempSignatureCounts[signature] ?? 0) + 1
                        tempSignatureCounts[signature] = nextCount
                        if nextCount > maxRepeatsPerSignature {
                            abortRepeatedTool = (toolCall.name, toolCall.id, nextCount)
                            break
                        }
                    }

                    if let abortRepeatedTool {
                        await AIToolTraceLogger.shared.log(type: "tool.loop_abort_repeated_tool", data: [
                            "tool": abortRepeatedTool.name,
                            "toolCallId": abortRepeatedTool.id,
                            "signatureCount": abortRepeatedTool.nextCount,
                            "maxRepeats": maxRepeatsPerSignature
                        ])

                        currentResponse = AIServiceResponse(
                            content: "Stopped: the agent repeatedly requested the same tool call (\(abortRepeatedTool.name)) without making progress. Try using index_list_files / index_search_text to discover the correct file path before reading it.",
                            toolCalls: nil
                        )
                        break
                    }

                    toolCallSignatureCounts = tempSignatureCounts
                    
                    // 1. Immediately record the Assistant's Request (with tool calls) to history
                    // This ensures the AI sees "I want to call X" before seeing "Result of X"
                    let split = Self.splitReasoning(from: currentResponse.content ?? "")
                    let assistantMsg = ChatMessage(
                        role: .assistant,
                        content: split.content,
                        reasoning: split.reasoning,
                        toolCalls: toolCalls
                    )
                    
                    await MainActor.run {
                        self.messages.append(assistantMsg)
                    }
                    
                    // 2. Execute Tools
                    var toolResults: [String] = []
                    
                    for toolCall in toolCalls {
                        let targetFile = toolCall.arguments["path"] as? String

                        await AIToolTraceLogger.shared.log(type: "tool.execute_start", data: [
                            "tool": toolCall.name,
                            "toolCallId": toolCall.id,
                            "targetPath": targetFile as Any,
                            "argumentKeys": Array(toolCall.arguments.keys).sorted()
                        ])
                        
                        // "Executing" indicator (UI only really, but we add to messages for now)
                        await MainActor.run {
                            let executingMsg = ChatMessage(
                                role: .tool,
                                content: "Executing \(toolCall.name)...",
                                toolName: toolCall.name,
                                toolStatus: .executing,
                                targetFile: targetFile,
                                toolCallId: toolCall.id
                            )
                            self.messages.append(executingMsg)
                        }
                        
                        // Execute
                        if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
                            do {
                                let result = try await tool.execute(arguments: toolCall.arguments)

                                await AIToolTraceLogger.shared.log(type: "tool.execute_success", data: [
                                    "tool": toolCall.name,
                                    "toolCallId": toolCall.id,
                                    "resultLength": result.count
                                ])
                                
                                // Update to "completed" message (Tool Output)
                                await MainActor.run {
                                    // Remove the temporary "executing" message to replace it with result.
                                    // For simplicity and history validity, let's keep it.
                                    if let lastMsg = self.messages.last, lastMsg.toolName == toolCall.name && lastMsg.toolStatus == .executing {
                                        self.messages.removeLast()
                                    }
                                    
                                    let completedMsg = ChatMessage(
                                        role: .tool,
                                        content: result,
                                        toolName: toolCall.name,
                                        toolStatus: .completed,
                                        targetFile: targetFile,
                                        toolCallId: toolCall.id
                                    )
                                    self.messages.append(completedMsg)
                                }
                                
                                toolResults.append(result)
                            } catch {
                                await AIToolTraceLogger.shared.log(type: "tool.execute_error", data: [
                                    "tool": toolCall.name,
                                    "toolCallId": toolCall.id,
                                    "error": error.localizedDescription
                                ])
                                // Failed
                                await MainActor.run {
                                    if let lastMsg = self.messages.last, lastMsg.toolName == toolCall.name && lastMsg.toolStatus == .executing {
                                        self.messages.removeLast()
                                    }

                                    let errorContent: String = {
                                        if toolCall.name == "index_read_file" {
                                            let msg = error.localizedDescription
                                            if msg.lowercased().hasPrefix("file not found") {
                                                return "Error: \(msg)\n\nHint: do not guess filenames. First use index_find_files(query: \"RegistrationPage\") or index_list_files(query: \"registration-app/src\") to discover the correct path, then call index_read_file with that exact path."
                                            }
                                        }
                                        return "Error: \(error.localizedDescription)"
                                    }()

                                    let failedMsg = ChatMessage(
                                        role: .tool,
                                        content: errorContent,
                                        toolName: toolCall.name,
                                        toolStatus: .failed,
                                        targetFile: targetFile,
                                        toolCallId: toolCall.id
                                    )
                                    self.messages.append(failedMsg)
                                }
                            }
                        } else {
                            await AIToolTraceLogger.shared.log(type: "tool.not_found", data: [
                                "tool": toolCall.name,
                                "toolCallId": toolCall.id
                            ])
                            // Tool not found
                            await MainActor.run {
                                let failedMsg = ChatMessage(
                                    role: .tool,
                                    content: "Tool not found",
                                    toolName: toolCall.name,
                                    toolStatus: .failed,
                                    targetFile: targetFile,
                                    toolCallId: toolCall.id
                                )
                                self.messages.append(failedMsg)
                            }
                        }
                    }
                    
                    // 3. Send updated history (with tool outputs) back to AI
                    // We don't send "toolFeedback" string anymore, we send the updated `self.messages`
                    currentResponse = try await sendMessageWithRetry(
                        messages: self.messages,
                        context: context,
                        tools: availableTools,
                        mode: currentMode,
                        projectRoot: projectRoot
                    )

                    await AIToolTraceLogger.shared.log(type: "chat.ai_response", data: [
                        "contentLength": currentResponse.content?.count ?? 0,
                        "toolCalls": currentResponse.toolCalls?.count ?? 0,
                        "iteration": toolIteration
                    ])
                }

                if let remainingToolCalls = currentResponse.toolCalls, !remainingToolCalls.isEmpty {
                    await AIToolTraceLogger.shared.log(type: "tool.loop_abort_iteration_limit", data: [
                        "maxIterations": maxIterations,
                        "iteration": toolIteration,
                        "remainingToolCalls": remainingToolCalls.count,
                        "mode": self.currentMode.rawValue
                    ])

                    currentResponse = AIServiceResponse(
                        content: "Stopped: the agent requested additional tool calls but hit the tool-iteration limit (\(maxIterations)). This usually means it got stuck. Please retry, or narrow the request so it can complete in fewer tool steps.",
                        toolCalls: nil
                    )
                }
                
                // Final Response (Answer)
                let splitFinal = Self.splitReasoning(from: currentResponse.content ?? "No response received.")
                let finalContent = splitFinal.content

                await AIToolTraceLogger.shared.log(type: "chat.final_response", data: [
                    "contentLength": finalContent.count,
                    "mode": self.currentMode.rawValue
                ])
                
                await MainActor.run {
                    self.messages.append(ChatMessage(role: .assistant, content: finalContent, reasoning: splitFinal.reasoning))
                    self.isSending = false
                    self.saveConversationHistory()
                }
            } catch {
                await AIToolTraceLogger.shared.log(type: "chat.error", data: [
                    "error": error.localizedDescription
                ])
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
        let delayNs: UInt64 = 5_000_000_000

        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let augmentedContext = ContextBuilder.buildContext(
                    userInput: messages.last?.content ?? "",
                    explicitContext: context,
                    index: codebaseIndex
                )
                return try await aiService.sendMessage(messages, context: augmentedContext, tools: tools, mode: mode, projectRoot: projectRoot)
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delayNs)
                }
            }
        }

        throw lastError ?? NSError(domain: "ConversationManager", code: -1)
    }

    private static func shouldForceToolFollowup(content: String) -> Bool {
        let text = content.lowercased()
        if text.isEmpty { return false }

        // Heuristic: if the assistant claims it will implement/patch/change/run and didn't emit tool calls.
        let triggers = [
            "i will implement",
            "i'll implement",
            "i will update",
            "i'll update",
            "i will patch",
            "i'll patch",
            "i will fix",
            "i'll fix",
            "i am going to implement",
            "i'm going to implement",
            "next i will",
            "now i will"
        ]

        return triggers.contains(where: { text.contains($0) })
    }

    static func splitReasoning(from text: String) -> (reasoning: String?, content: String) {
        guard !text.isEmpty else { return (nil, "") }

        let startTag = "<ide_reasoning>"
        let endTag = "</ide_reasoning>"

        guard let startRange = text.range(of: startTag),
              let endRange = text.range(of: endTag) else {
            return (nil, text)
        }

        guard startRange.lowerBound < endRange.lowerBound else {
            return (nil, text)
        }

        let reasoningStart = startRange.upperBound
        let reasoningEnd = endRange.lowerBound
        let reasoning = String(text[reasoningStart..<reasoningEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        var remaining = text
        remaining.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        let cleaned = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        return (reasoning.isEmpty ? nil : reasoning, cleaned)
    }
    
    func clearConversation() {
        messages.removeAll()
        messages.append(ChatMessage(
            role: .assistant,
            content: "Conversation cleared. How can I assist you now?"
        ))
        saveConversationHistory()
    }
    
    // MARK: - Context Actions
    
    func explainCode(_ code: String) {
        isSending = true
        error = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let response = try await aiService.explainCode(code)
                await MainActor.run {
                    self.messages.append(ChatMessage(
                        role: .user,
                        content: "Explain this code",
                        codeContext: code
                    ))
                    self.messages.append(ChatMessage(role: .assistant, content: response))
                    self.isSending = false
                    self.saveConversationHistory()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to explain code: \(error.localizedDescription)"
                    self.isSending = false
                }
            }
        }
    }
    
    func refactorCode(_ code: String, instructions: String) {
        isSending = true
        error = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let response = try await aiService.refactorCode(code, instructions: instructions)
                await MainActor.run {
                    self.messages.append(ChatMessage(
                        role: .user,
                        content: "Refactor this code: \(instructions)",
                        codeContext: code
                    ))
                    self.messages.append(ChatMessage(
                        role: .assistant,
                        content: "Here's the refactored code:",
                        codeContext: response
                    ))
                    self.isSending = false
                    self.saveConversationHistory()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to refactor code: \(error.localizedDescription)"
                    self.isSending = false
                }
            }
        }
    }
    
    // MARK: - Conversation History Management
    
    private func saveConversationHistory() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("Failed to save conversation history: \(error)")
        }
    }
    
    private func loadConversationHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            print("Failed to load conversation history: \(error)")
        }
    }
}