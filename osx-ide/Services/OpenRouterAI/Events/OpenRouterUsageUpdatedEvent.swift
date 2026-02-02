import Foundation

public struct OpenRouterUsageUpdatedEvent: Event {
    public struct Usage: Sendable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int

        public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }

    public let modelId: String
    public let usage: Usage
    public let contextLength: Int?

    public init(modelId: String, usage: Usage, contextLength: Int?) {
        self.modelId = modelId
        self.usage = usage
        self.contextLength = contextLength
    }
}
