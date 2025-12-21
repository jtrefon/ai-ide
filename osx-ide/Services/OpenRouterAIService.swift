//
//  OpenRouterAIService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation

actor OpenRouterAIService: AIService {
    private let settingsStore: OpenRouterSettingsStore
    private let client: OpenRouterAPIClient
    
    init(
        settingsStore: OpenRouterSettingsStore = OpenRouterSettingsStore(),
        client: OpenRouterAPIClient = OpenRouterAPIClient()
    ) {
        self.settingsStore = settingsStore
        self.client = client
    }
    
    func sendMessage(_ message: String, context: String?) async throws -> String {
        try await performChat(prompt: message, context: context)
    }
    
    func explainCode(_ code: String) async throws -> String {
        let prompt = "Explain the following code in clear, concise terms:\n\n\(code)"
        return try await performChat(prompt: prompt, context: nil)
    }
    
    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let prompt = "Refactor this code using the following instructions:\n\(instructions)\n\nCode:\n\(code)"
        return try await performChat(prompt: prompt, context: nil)
    }
    
    func generateCode(_ prompt: String) async throws -> String {
        let message = "Generate code for the following request:\n\(prompt)"
        return try await performChat(prompt: message, context: nil)
    }
    
    func fixCode(_ code: String, error: String) async throws -> String {
        let prompt = "Fix this code. Error message:\n\(error)\n\nCode:\n\(code)"
        return try await performChat(prompt: prompt, context: nil)
    }
    
    private func performChat(prompt: String, context: String?) async throws -> String {
        let settings = settingsStore.load()
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !apiKey.isEmpty else {
            throw AppError.aiServiceError("OpenRouter API key is missing.")
        }
        guard !model.isEmpty else {
            throw AppError.aiServiceError("OpenRouter model is not set.")
        }
        
        let systemContent = systemPrompt.isEmpty
            ? "You are a helpful, concise coding assistant."
            : systemPrompt
        var messages = [OpenRouterChatMessage(role: "system", content: systemContent)]
        
        if let context, !context.isEmpty {
            messages.append(OpenRouterChatMessage(
                role: "user",
                content: "Context:\n\(context)"
            ))
        }
        
        messages.append(OpenRouterChatMessage(role: "user", content: prompt))
        
        let request = OpenRouterChatRequest(
            model: model,
            messages: messages,
            maxTokens: 1024,
            temperature: 0.2
        )
        
        let body = try JSONEncoder().encode(request)
        let data = try await client.chatCompletion(
            apiKey: apiKey,
            baseURL: settings.baseURL,
            appName: "OSX IDE",
            referer: "",
            body: body
        )
        
        let response = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw AppError.aiServiceError("OpenRouter response was empty.")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct OpenRouterChatRequest: Encodable {
    let model: String
    let messages: [OpenRouterChatMessage]
    let maxTokens: Int
    let temperature: Double
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct OpenRouterChatMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
