//
//  AIService.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation

struct AIServiceResponse: Sendable {
    let content: String?
    let toolCalls: [AIToolCall]?
}

protocol AIService: Sendable {
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?) async throws -> AIServiceResponse
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse
    func sendMessage(_ messages: [ChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse
    func explainCode(_ code: String) async throws -> String
    func refactorCode(_ code: String, instructions: String) async throws -> String
    func generateCode(_ prompt: String) async throws -> String
    func fixCode(_ code: String, error: String) async throws -> String
}

// MARK: - Configurable AI Service Implementation
final class ConfigurableAIService: AIService, @unchecked Sendable {
    private let responseDelay: UInt64
    private let responses: [String]
    private let customResponses: [String: String]
    
    init(
        responseDelay: UInt64 = AppConstants.AI.defaultResponseDelay,
        responses: [String] = [],
        customResponses: [String: String] = [:]
    ) {
        self.responseDelay = responseDelay
        self.responses = responses.isEmpty ? [
            "I understand you're asking about this. Here's my analysis...",
            "That's an interesting question. Based on my knowledge...",
            "I recommend checking the documentation for more details.",
            "I've analyzed your request and here's my suggestion...",
            "Thank you for your question. Let me provide some insights."
        ] : responses
        self.customResponses = customResponses
    }
    
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?) async throws -> AIServiceResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: responseDelay)
        
        // Check for custom response first
        if let customResponse = customResponses[message] {
            return AIServiceResponse(content: customResponse, toolCalls: nil)
        }
        
        // Return configured or default responses
        let content = responses.randomElement() ?? "I'm here to help with your coding questions!"
        return AIServiceResponse(content: content, toolCalls: nil)
    }
    
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        return try await sendMessage(message, context: context, tools: tools, mode: mode)
    }
    
    func sendMessage(_ messages: [ChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        // Simple mock implementation that just uses the last user message
        let lastUserMessage = messages.last { $0.role == .user }?.content ?? ""
        return try await sendMessage(lastUserMessage, context: context, tools: tools, mode: mode)
    }
    
    func explainCode(_ code: String) async throws -> String {
        try await Task.sleep(nanoseconds: responseDelay)
        return "This code appears to be implementing a \(detectCodePattern(code)). It works by..."
    }
    
    func refactorCode(_ code: String, instructions: String) async throws -> String {
        try await Task.sleep(nanoseconds: responseDelay)
        return "// Refactored code based on: \(instructions)\n\(code)"
    }
    
    func generateCode(_ prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: responseDelay)
        return "// Generated code for: \(prompt)\nfunc generatedFunction() {\n    // Implementation here\n}"
    }
    
    func fixCode(_ code: String, error: String) async throws -> String {
        try await Task.sleep(nanoseconds: responseDelay)
        return "// Fixed code. Resolved: \(error)\n\(code)"
    }
    
    private func detectCodePattern(_ code: String) -> String {
        if code.contains("func") {
            return "function"
        } else if code.contains("class") {
            return "class"
        } else if code.contains("struct") {
            return "struct"
        } else {
            return "code snippet"
        }
    }
}

// MARK: - Backward Compatibility

/// Backward compatibility alias for the configurable service
typealias SampleAIService = ConfigurableAIService