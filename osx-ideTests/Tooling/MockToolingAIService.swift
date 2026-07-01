import Foundation
@testable import osx_ide

final class MockToolingAIService: AIServiceProtocol, @unchecked Sendable {
    enum Behavior: Sendable {
        case respondWithText(String)
        case respondWithToolCall(toolName: String, arguments: [String: String])
        case respondWithMultipleToolCalls([(toolName: String, arguments: [String: String])])
        case respondEmpty
        case throwError(String)
    }

    private let behavior: Behavior
    private var callCount = 0
    init(behavior: Behavior) { self.behavior = behavior }

    func complete(msgs: [ChatMessage], tools: [[String: Any]]?) async throws -> AIServResp {
        callCount += 1
        switch behavior {
        case .respondWithText(let text):
            return AIServResp(content: text, toolCalls: nil)
        case .respondWithToolCall(let toolName, let args):
            return AIServResp(content: nil, toolCalls: [AIToolCall(id: "c\(callCount)", name: toolName, arguments: args)])
        case .respondWithMultipleToolCalls(let calls):
            let tcs = calls.enumerated().map { AIToolCall(id: "c\($0)", name: $1.toolName, arguments: $1.arguments) }
            return AIServResp(content: nil, toolCalls: tcs)
        case .respondEmpty:
            return AIServResp(content: nil, toolCalls: [])
        case .throwError(let msg):
            struct E: LocalizedError { let m: String; var errorDescription: String? { m } }
            throw E(m: msg)
        }
    }
}
