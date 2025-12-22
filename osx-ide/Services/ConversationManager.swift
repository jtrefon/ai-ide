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
    private let historyKey = "AIChatHistory"
    private var cancellables = Set<AnyCancellable>()
    
    // Project root for sandboxing
    var projectRoot: URL
    
    private var pathValidator: PathValidator {
        return PathValidator(projectRoot: projectRoot)
    }
    
    private var allTools: [AITool] {
        let validator = pathValidator
        return [
            // Project awareness tools
            GetProjectStructureTool(projectRoot: projectRoot),
            ListAllFilesTool(projectRoot: projectRoot),
            FindFileRegexTool(projectRoot: projectRoot),
            
            // File operation tools
            ReadFileTool(fileSystemService: fileSystemService, pathValidator: validator),
            WriteFileTool(fileSystemService: fileSystemService, pathValidator: validator),
            CreateFileTool(pathValidator: validator),
            DeleteFileTool(pathValidator: validator),
            ListFilesTool(pathValidator: validator),
            ReplaceInFileTool(fileSystemService: fileSystemService, pathValidator: validator),
            
            // Search and execution
            GrepTool(pathValidator: validator),
            FindFileTool(pathValidator: validator),
            RunCommandTool()
        ]
    }
    
    private var availableTools: [AITool] {
        return currentMode.allowedTools(from: allTools)
    }
    
    init(aiService: AIService = SampleAIService(), errorManager: ErrorManagerProtocol, fileSystemService: FileSystemService = FileSystemService(), projectRoot: URL? = nil) {
        self.aiService = aiService
        self.errorManager = errorManager
        self.fileSystemService = fileSystemService
        self.projectRoot = projectRoot ?? FileManager.default.homeDirectoryForCurrentUser
        loadConversationHistory()
        
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
    
    func updateProjectRoot(_ newRoot: URL) {
        projectRoot = newRoot
    }
    
    func sendMessage() {
        sendMessage(context: nil)
    }

    func sendMessage(context: String? = nil) {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
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
                // Initial call with full history
                var currentResponse = try await sendMessageWithRetry(
                    messages: self.messages,
                    context: context,
                    tools: availableTools,
                    mode: currentMode,
                    projectRoot: projectRoot
                )
                
                // Tool calling loop
                var toolIteration = 0
                let maxIterations = 5
                
                // Check if response has tool calls
                while let toolCalls = currentResponse.toolCalls, !toolCalls.isEmpty && toolIteration < maxIterations {
                    toolIteration += 1
                    
                    // 1. Immediately record the Assistant's Request (with tool calls) to history
                    // This ensures the AI sees "I want to call X" before seeing "Result of X"
                    let assistantMsg = ChatMessage(
                        role: .assistant,
                        content: currentResponse.content ?? "", // May form "thought"
                        toolCalls: toolCalls
                    )
                    
                    await MainActor.run {
                        self.messages.append(assistantMsg)
                    }
                    
                    // 2. Execute Tools
                    var toolResults: [String] = []
                    
                    for toolCall in toolCalls {
                        let targetFile = toolCall.arguments["path"] as? String
                        
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
                                // Failed
                                await MainActor.run {
                                    if let lastMsg = self.messages.last, lastMsg.toolName == toolCall.name && lastMsg.toolStatus == .executing {
                                        self.messages.removeLast()
                                    }
                                    let failedMsg = ChatMessage(
                                        role: .tool,
                                        content: "Error: \(error.localizedDescription)",
                                        toolName: toolCall.name,
                                        toolStatus: .failed,
                                        targetFile: targetFile,
                                        toolCallId: toolCall.id
                                    )
                                    self.messages.append(failedMsg)
                                }
                            }
                        } else {
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
                }
                
                // Final Response (Answer)
                let finalContent = currentResponse.content ?? "No response received."
                
                await MainActor.run {
                    self.messages.append(ChatMessage(role: .assistant, content: finalContent))
                    self.isSending = false
                    self.saveConversationHistory()
                }
            } catch {
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
                return try await aiService.sendMessage(messages, context: context, tools: tools, mode: mode, projectRoot: projectRoot)
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delayNs)
                }
            }
        }

        throw lastError ?? NSError(domain: "ConversationManager", code: -1)
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