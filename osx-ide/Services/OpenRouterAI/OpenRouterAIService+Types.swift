import Foundation

extension OpenRouterAIService {
    internal struct BuildSystemContentInput {
        let systemPrompt: String
        let hasTools: Bool
        let toolPromptMode: ToolPromptMode
        let mode: AIMode?
        let projectRoot: URL?
        let reasoningMode: ReasoningMode
        let stage: AIRequestStage?
        let useNativeReasoning: Bool
    }

    struct NativeReasoningConfiguration: Equatable, Sendable {
        let enabled: Bool
        let effort: String?
        let exclude: Bool
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
        let providerName: String
        let baseURL: String
        let streaming: Bool
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
        let reasoningMode: ReasoningMode
        let toolPromptMode: ToolPromptMode
    }

    struct ChatPreparation {
        let requestId: String
        let settings: SettingsSnapshot
        let finalMessages: [OpenRouterChatMessage]
        let toolDefinitions: [[String: Any]]?
        let toolChoice: String?
        let nativeReasoningConfiguration: NativeReasoningConfiguration?
    }
}
