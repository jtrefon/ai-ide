import Foundation

public protocol AIService: Sendable {
    func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse
    func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse
    func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse
}

public protocol RemoteAIAccountStatusRefreshing: Sendable {
    func refreshAccountBalance(runId: String?) async
}
