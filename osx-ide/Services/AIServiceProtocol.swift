import Foundation

public protocol AIService: Sendable {
    func sendMessage(
        _ message: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?
    ) async throws -> AIServiceResponse

    func sendMessage(
        _ message: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async throws -> AIServiceResponse

    func sendMessage(
        _ messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async throws -> AIServiceResponse

    func explainCode(_ code: String) async throws -> String
    func refactorCode(_ code: String, instructions: String) async throws -> String
    func generateCode(_ prompt: String) async throws -> String
    func fixCode(_ code: String, error: String) async throws -> String
}
