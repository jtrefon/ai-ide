import Foundation

extension OpenRouterAIService {
    internal struct BuildSystemContentInput {
        let systemPrompt: String
        let hasTools: Bool
        let toolPromptMode: ToolPromptMode
        let mode: AIMode?
        let projectRoot: URL?
        let reasoningEnabled: Bool
    }

    struct OpenRouterChatInput {
        let prompt: String
        let context: String?
        let tools: [AITool]?
        let mode: AIMode?
        let projectRoot: URL?
    }

    struct OpenRouterChatHistoryInput {
        let messages: [OpenRouterChatMessage]
        let context: String?
        let tools: [AITool]?
        let mode: AIMode?
        let projectRoot: URL?
        let runId: String?
        let stage: AIRequestStage?
    }

    internal struct RequestStartContext {
        let requestId: String
        let model: String
        let messageCount: Int
        let toolCount: Int
        let mode: AIMode?
        let projectRoot: URL?
        let runId: String?
        let stage: AIRequestStage?
    }

    struct SettingsSnapshot {
        let apiKey: String
        let model: String
        let systemPrompt: String
        let baseURL: String
        let reasoningEnabled: Bool
        let toolPromptMode: ToolPromptMode
    }

    struct ChatPreparation {
        let requestId: String
        let settings: SettingsSnapshot
        let finalMessages: [OpenRouterChatMessage]
        let toolDefinitions: [[String: Any]]?
        let toolChoice: String?
    }
}
