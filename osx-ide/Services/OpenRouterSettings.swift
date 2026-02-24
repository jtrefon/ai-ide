import Foundation

enum ToolPromptMode: String, Equatable {
    case fullStatic
    case concise
}

struct OpenRouterSettings: Equatable {
    var apiKey: String
    var model: String
    var baseURL: String
    var systemPrompt: String
    var reasoningEnabled: Bool
    var toolPromptMode: ToolPromptMode
    var ragEnabledDuringToolLoop: Bool

    static let empty = OpenRouterSettings(
        apiKey: "",
        model: "",
        baseURL: "https://openrouter.ai/api/v1",
        systemPrompt: "",
        reasoningEnabled: true,
        toolPromptMode: .fullStatic,
        ragEnabledDuringToolLoop: true
    )
}
