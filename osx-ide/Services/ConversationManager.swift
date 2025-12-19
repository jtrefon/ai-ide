//
//  ConversationManager.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Combine

@MainActor
class ConversationManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isSending: Bool = false
    @Published var error: String? = nil
    
    private let aiService: AIService
    private let historyKey = "AIChatHistory"
    private var cancellables = Set<AnyCancellable>()
    
    init(aiService: AIService = SampleAIService()) {
        self.aiService = aiService
        loadConversationHistory()
        
        // If no messages, initialize with a welcome message
        if messages.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI coding assistant. How can I help you today?"
            ))
        }
    }
    
    func sendMessage() {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Add user message to conversation
        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)
        
        // Clear input and set sending state
        let userInput = currentInput
        currentInput = ""
        isSending = true
        error = nil
        
        // Save conversation history
        saveConversationHistory()
        
        // Get AI response using the AI service
        Task {
            do {
                let response = try await aiService.sendMessage(userInput, context: nil)
                await MainActor.run {
                    self.messages.append(ChatMessage(role: .assistant, content: response))
                    self.isSending = false
                    // Save after AI response
                    self.saveConversationHistory()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to get AI response: \(error.localizedDescription)"
                    self.isSending = false
                }
            }
        }
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
        
        Task {
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
        
        Task {
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