import Foundation

@MainActor
final class QAReviewHandler {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
    }

    func performToolOutputReviewIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        qaReviewEnabled: Bool,
        toolResults: [ChatMessage],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        guard qaReviewEnabled, mode == .agent else { return response }
        guard !toolResults.isEmpty else { return response }

        let toolSummary = toolResultsSummaryText(toolResults)
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.isEmpty else { return response }

        let qaSystem = ChatMessage(
            role: .system,
            content: "You are the QA reviewer for tool execution results. Validate the assistant draft against " +
                "the tool outputs and user request. If steps are missing or tool failures occurred, " +
                "revise the draft to include recovery guidance or next actions. " +
                "Return the improved draft response only. Do not call tools. Do not include <ide_reasoning>."
        )
        let qaUser = ChatMessage(
            role: .user,
            content: "User request:\n\(userInput)\n\nTool outputs:\n\(toolSummary)\n\nDraft response:\n\(draft)"
        )

        let qaResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [qaSystem, qaUser],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        Task.detached(priority: .utility) {
            await AppLogger.shared.info(
                category: .conversation,
                message: "qa.tool_output_review_completed",
                context: AppLogger.LogCallContext(metadata: [
                    "conversationId": self.historyCoordinator.currentConversationId,
                    "hasResponse": (qaResponse.content?.isEmpty == false)
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: self.historyCoordinator.currentConversationId,
                type: "qa.tool_output_review_completed",
                data: [
                    "responseLength": qaResponse.content?.count ?? 0
                ]
            )
        }

        await appendRunSnapshot(payload: RunSnapshotPayload(
            runId: runId,
            conversationId: historyCoordinator.currentConversationId,
            phase: "tool_output_review",
            iteration: nil,
            userInput: userInput,
            assistantDraft: qaResponse.content,
            failureReason: nil,
            toolCalls: [],
            toolResults: toolResults
        ))

        let qaContent = qaResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = qaContent?.isEmpty == false ? qaResponse.content : response.content
        return AIServiceResponse(content: finalContent, toolCalls: nil)
    }

    func performQualityReviewIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        qaReviewEnabled: Bool,
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        guard qaReviewEnabled, mode == .agent else { return response }
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.isEmpty else { return response }

        let qaSystem = ChatMessage(
            role: .system,
            content: "You are the QA reviewer. Review the assistant draft response for correctness, completeness, " +
                "and adherence to the user request. Return the improved final response only. " +
                "If the draft is already perfect, repeat it verbatim. Do not call tools. Do not include <ide_reasoning>."
        )
        let qaUser = ChatMessage(
            role: .user,
            content: "Review and refine this draft response:\n\n\(draft)"
        )

        let qaResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [qaSystem, qaUser],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        Task.detached(priority: .utility) {
            await AppLogger.shared.info(
                category: .conversation,
                message: "qa.quality_review_completed",
                context: AppLogger.LogCallContext(metadata: [
                    "conversationId": self.historyCoordinator.currentConversationId,
                    "hasResponse": (qaResponse.content?.isEmpty == false)
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: self.historyCoordinator.currentConversationId,
                type: "qa.quality_review_completed",
                data: [
                    "responseLength": qaResponse.content?.count ?? 0
                ]
            )
        }

        await appendRunSnapshot(payload: RunSnapshotPayload(
            runId: runId,
            conversationId: historyCoordinator.currentConversationId,
            phase: "quality_review",
            iteration: nil,
            userInput: userInput,
            assistantDraft: qaResponse.content,
            failureReason: nil,
            toolCalls: [],
            toolResults: []
        ))

        let qaContent = qaResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = qaContent?.isEmpty == false ? qaResponse.content : response.content
        return AIServiceResponse(content: finalContent, toolCalls: nil)
    }

    private func toolResultsSummaryText(_ toolResults: [ChatMessage]) -> String {
        let lines = toolResults.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let status = message.toolStatus?.rawValue ?? "unknown"
            let preview = truncate(toolOutputText(from: message), limit: 400)
            return "- \(message.toolName ?? "unknown_tool") (\(toolCallId)) [\(status)]: \(preview)"
        }
        return lines.isEmpty ? "No tool outputs." : lines.joined(separator: "\n")
    }

    private func toolOutputText(from message: ChatMessage) -> String {
        guard message.isToolExecution else { return message.content }
        if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
            if let payload = envelope.payload?.trimmingCharacters(in: .whitespacesAndNewlines),
               !payload.isEmpty {
                return payload
            }
            return envelope.message
        }
        return message.content
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }

    private func appendRunSnapshot(payload: RunSnapshotPayload) async {
        let snapshot = OrchestrationRunSnapshot(
            runId: payload.runId,
            conversationId: payload.conversationId,
            phase: payload.phase,
            iteration: payload.iteration,
            timestamp: Date(),
            userInput: payload.userInput,
            assistantDraft: payload.assistantDraft,
            failureReason: payload.failureReason,
            toolCalls: toolCallSummaries(payload.toolCalls),
            toolResults: toolResultSummaries(payload.toolResults)
        )
        try? await OrchestrationRunStore.shared.appendSnapshot(snapshot)
    }

    private func toolCallSummaries(_ toolCalls: [AIToolCall]) -> [OrchestrationRunSnapshot.ToolCallSummary] {
        toolCalls.map {
            OrchestrationRunSnapshot.ToolCallSummary(
                id: $0.id,
                name: $0.name,
                argumentKeys: Array($0.arguments.keys).sorted()
            )
        }
    }

    private func toolResultSummaries(_ toolResults: [ChatMessage]) -> [OrchestrationRunSnapshot.ToolResultSummary] {
        toolResults.compactMap { message in
            guard let toolCallId = message.toolCallId else { return nil }
            let output = toolOutputText(from: message)
            return OrchestrationRunSnapshot.ToolResultSummary(
                toolCallId: toolCallId,
                toolName: message.toolName ?? "unknown_tool",
                status: message.toolStatus?.rawValue ?? "unknown",
                targetFile: message.targetFile,
                outputPreview: truncate(output, limit: 1200)
            )
        }
    }
}
