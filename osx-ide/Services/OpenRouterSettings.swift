import Foundation

enum ToolPromptMode: String, Equatable {
    case fullStatic
    case concise
}

enum ReasoningMode: String, CaseIterable, Equatable {
    case none
    case model
    case agent
    case modelAndAgent

    var includesAgentReasoning: Bool {
        switch self {
        case .agent, .modelAndAgent:
            return true
        case .none, .model:
            return false
        }
    }

    var includesModelReasoning: Bool {
        switch self {
        case .model, .modelAndAgent:
            return true
        case .none, .agent:
            return false
        }
    }

    var modelReasoningPromptKey: String {
        includesModelReasoning
            ? "ConversationFlow/Corrections/model_reasoning_enabled"
            : "ConversationFlow/Corrections/model_reasoning_disabled"
    }
}

struct OpenRouterSettings: Equatable {
    var apiKey: String
    var model: String
    var baseURL: String
    var systemPrompt: String
    var reasoningMode: ReasoningMode
    var toolPromptMode: ToolPromptMode
    var ragEnabledDuringToolLoop: Bool

    static let empty = OpenRouterSettings(
        apiKey: "",
        model: "",
        baseURL: "https://openrouter.ai/api/v1",
        systemPrompt: "",
        reasoningMode: .modelAndAgent,
        toolPromptMode: .fullStatic,
        ragEnabledDuringToolLoop: true
    )
}
