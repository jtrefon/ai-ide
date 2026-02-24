import Foundation

public protocol AIService: Sendable {
    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse
    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse

    /// Send a message with streaming support - publishes chunks via EventBus
    /// Default implementation falls back to non-streaming for services that don't support streaming
    func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse

    func explainCode(_ code: String) async throws -> String
    func refactorCode(_ code: String, instructions: String) async throws -> String
    func generateCode(_ prompt: String) async throws -> String
    func fixCode(_ code: String, error: String) async throws -> String
}

// Default implementation for services that don't support streaming
extension AIService {
    /// Default implementation - falls back to non-streaming
    public func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
        return try await sendMessage(request)
    }
}
