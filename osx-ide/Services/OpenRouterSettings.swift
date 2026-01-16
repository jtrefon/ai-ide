import Foundation

struct OpenRouterSettings: Equatable {
    var apiKey: String
    var model: String
    var baseURL: String
    var systemPrompt: String
    var reasoningEnabled: Bool

    static let empty = OpenRouterSettings(
        apiKey: "",
        model: "",
        baseURL: "https://openrouter.ai/api/v1",
        systemPrompt: "",
        reasoningEnabled: true
    )
}
