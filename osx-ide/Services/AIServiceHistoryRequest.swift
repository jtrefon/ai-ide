import Foundation

public enum AIRequestStage: String, Codable, Sendable {
    case warmup
    case initial_response
    case strategic_planning
    case tactical_planning
    case tool_loop
    case final_response
    case qa_tool_output_review
    case qa_quality_review
    case other

    var reasoningPromptKey: String {
        switch self {
        case .tool_loop:
            return "ConversationFlow/Corrections/reasoning_optional_tool_loop"
        default:
            return "ConversationFlow/Corrections/reasoning_optional_general"
        }
    }

    static func reasoningPromptKey(for stage: AIRequestStage?) -> String {
        stage?.reasoningPromptKey ?? AIRequestStage.other.reasoningPromptKey
    }

    static func reasoningPromptKeyIfNeeded(
        reasoningEnabled: Bool,
        mode: AIMode?,
        stage: AIRequestStage?
    ) -> String? {
        guard reasoningEnabled, mode == .agent else { return nil }
        guard stage != .initial_response else { return nil }
        return reasoningPromptKey(for: stage)
    }

    static func reasoningPromptIfNeeded(
        reasoningEnabled: Bool,
        mode: AIMode?,
        stage: AIRequestStage?,
        projectRoot: URL?
    ) throws -> String? {
        guard let promptKey = reasoningPromptKeyIfNeeded(
            reasoningEnabled: reasoningEnabled,
            mode: mode,
            stage: stage
        ) else {
            return nil
        }
        return try PromptRepository.shared.prompt(key: promptKey, projectRoot: projectRoot)
    }
}

public struct AIServiceHistoryRequest: Sendable {
    public let messages: [ChatMessage]
    public let context: String?
    public let tools: [AITool]?
    public let mode: AIMode?
    public let projectRoot: URL?
    public let runId: String?
    public let stage: AIRequestStage?
    public let conversationId: String?

    public init(
        messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?,
        runId: String? = nil,
        stage: AIRequestStage? = nil,
        conversationId: String? = nil
    ) {
        self.messages = messages
        self.context = context
        self.tools = tools
        self.mode = mode
        self.projectRoot = projectRoot
        self.runId = runId
        self.stage = stage
        self.conversationId = conversationId
    }
}
