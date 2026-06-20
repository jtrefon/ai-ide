import Foundation

enum LocalModelToolCallFormat: Sendable {
    case json
    case gemma
}

protocol LocalModelAdapter: Sendable {
    var contextLength: Int { get }
    var toolCallFormat: LocalModelToolCallFormat { get }
    var supportsReasoning: Bool { get }
    var supportsTurboQuant: Bool { get }

    func tokenize(_ text: String) -> [Int]
    func decode(_ tokenIds: [Int]) -> String
    func formatPrompt(messages: [ChatMessage], tools: [AITool]?, mode: AIMode) -> String?
    func additionalContext(enableThinking: Bool) -> [String: any Sendable]
}
