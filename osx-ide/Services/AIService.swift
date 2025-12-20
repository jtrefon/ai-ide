//
//  AIService.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation

protocol AIService: Sendable {
    func sendMessage(_ message: String, context: String?) async throws -> String
    func explainCode(_ code: String) async throws -> String
    func refactorCode(_ code: String, instructions: String) async throws -> String
    func generateCode(_ prompt: String) async throws -> String
    func fixCode(_ code: String, error: String) async throws -> String
}

// MARK: - Sample AI Service Implementation
final class SampleAIService: AIService, @unchecked Sendable {
    func sendMessage(_ message: String, context: String?) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // In a real implementation, this would call an actual AI API
        let responses = [
            "I understand you're asking about '\(message)'. Here's my analysis...",
            "That's an interesting question about '\(message)'. Based on my knowledge...",
            "Regarding '\(message)', I recommend checking the documentation.",
            "I've analyzed your request '\(message)' and here's my suggestion..."
        ]
        
        return responses.randomElement() ?? "I'm here to help with your coding questions!"
    }
    
    func explainCode(_ code: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return "This code appears to be implementing a \(detectCodePattern(code)). It works by..."
    }
    
    func refactorCode(_ code: String, instructions: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return "// Refactored code based on: \(instructions)\n\(code)"
    }
    
    func generateCode(_ prompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        return "// Generated code for: \(prompt)\nfunc generatedFunction() {\n    // Implementation here\n}"
    }
    
    func fixCode(_ code: String, error: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
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