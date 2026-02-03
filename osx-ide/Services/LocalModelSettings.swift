import Foundation

enum LocalModelQuantization: String, CaseIterable, Hashable {
    case q4 = "4bit"
    case q8 = "8bit"
}

struct LocalModelSettings: Equatable {
    var isEnabled: Bool
    var selectedModelId: String
    var quantization: LocalModelQuantization
    var allowRemoteFallback: Bool
    var contextBudgetTokens: Int
    var maxAnswerTokens: Int
    var maxReasoningTokens: Int

    static let `default` = LocalModelSettings(
        isEnabled: false,
        selectedModelId: LocalModelCatalog.defaultModelId,
        quantization: .q8,
        allowRemoteFallback: false,
        contextBudgetTokens: 2048,
        maxAnswerTokens: 256,
        maxReasoningTokens: 512
    )
}
