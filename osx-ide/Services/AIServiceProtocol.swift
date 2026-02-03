import Foundation

public protocol AIService: Sendable {
    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse
    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse

    func explainCode(_ code: String) async throws -> String
    func refactorCode(_ code: String, instructions: String) async throws -> String
    func generateCode(_ prompt: String) async throws -> String
    func fixCode(_ code: String, error: String) async throws -> String
}

public protocol AIServiceStreaming: AIService {
    func sendMessageStream(
        _ request: AIServiceHistoryRequest,
        onChunk: @MainActor @Sendable @escaping (String) -> Void
    ) async throws -> AIServiceResponse
}
