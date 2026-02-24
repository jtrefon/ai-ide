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
        availableTools: [AITool],
        toolResults: [ChatMessage],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        guard qaReviewEnabled, mode == .agent else { return response }
        guard !toolResults.isEmpty else { return response }

        let toolSummary = ToolLoopUtilities.toolResultsSummaryText(toolResults)
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.isEmpty else { return response }

        let toolOutputReviewSystemPrompt = PromptRepository.shared.prompt(
            key: "ConversationFlow/QA/tool_output_review_system",
            defaultValue: "You are the QA reviewer for tool execution results. Validate the assistant draft against " +
                "the tool outputs and user request. Identify mistakes, omissions, and risk. " +
                "Return a QA report only (do not rewrite the assistant draft). " +
                "Do not call tools.",
            projectRoot: projectRoot
        )
        let qaSystem = ChatMessage(
            role: .system,
            content: toolOutputReviewSystemPrompt
        )
        let qaUser = ChatMessage(
            role: .user,
            content: "User request:\n\(userInput)\n\nTool outputs:\n\(toolSummary)\n\nDraft response:\n\(draft)\n\n" +
                "Produce:\n" +
                "- Summary\n" +
                "- Issues (bullets)\n" +
                "- Missing steps (bullets)\n" +
                "- Suggested next actions (bullets)"
        )

        let qaResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [qaSystem, qaUser],
                explicitContext: explicitContext,
                tools: readOnlyTools(from: availableTools),
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.qa_tool_output_review
            ))
            .get()

        let qaReport = qaResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !qaReport.isEmpty {
            historyCoordinator.append(
                ChatMessage(
                    role: .assistant,
                    content: "QA Review (advisory):\n\n\(qaReport)"
                )
            )
        }

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

        await ToolLoopUtilities.appendRunSnapshot(
            runId: runId,
            conversationId: historyCoordinator.currentConversationId,
            phase: "tool_output_review",
            iteration: nil,
            userInput: userInput,
            assistantDraft: qaResponse.content,
            failureReason: nil,
            toolCalls: [],
            toolResults: toolResults
        )

        return response
    }

    func performQualityReviewIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        mode: AIMode,
        projectRoot: URL,
        qaReviewEnabled: Bool,
        availableTools: [AITool],
        runId: String,
        userInput: String
    ) async throws -> AIServiceResponse {
        guard qaReviewEnabled, mode == .agent else { return response }
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.isEmpty else { return response }

        let qualityReviewSystemPrompt = PromptRepository.shared.prompt(
            key: "ConversationFlow/QA/quality_review_system",
            defaultValue: "You are the QA reviewer. Review the assistant draft response for correctness, completeness, " +
                "and adherence to the user request. Return a QA report only (do not rewrite the response). " +
                "Do not call tools.",
            projectRoot: projectRoot
        )
        let qaSystem = ChatMessage(
            role: .system,
            content: qualityReviewSystemPrompt
        )
        let qaUser = ChatMessage(
            role: .user,
            content: "User request:\n\(userInput)\n\nDraft response:\n\(draft)\n\n" +
                "Produce:\n" +
                "- Summary\n" +
                "- Issues (bullets)\n" +
                "- Missing steps (bullets)\n" +
                "- Suggested next actions (bullets)"
        )

        let qaResponse = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: [qaSystem, qaUser],
                explicitContext: explicitContext,
                tools: readOnlyTools(from: availableTools),
                mode: mode,
                projectRoot: projectRoot,
                runId: runId,
                stage: AIRequestStage.qa_quality_review
            ))
            .get()

        let qaReport = qaResponse.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !qaReport.isEmpty {
            historyCoordinator.append(
                ChatMessage(
                    role: .assistant,
                    content: "QA Review (advisory):\n\n\(qaReport)"
                )
            )
        }

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

        await ToolLoopUtilities.appendRunSnapshot(
            runId: runId,
            conversationId: historyCoordinator.currentConversationId,
            phase: "quality_review",
            iteration: nil,
            userInput: userInput,
            assistantDraft: qaResponse.content,
            failureReason: nil,
            toolCalls: [],
            toolResults: []
        )

        return response
    }

    private func readOnlyTools(from tools: [AITool]) -> [AITool] {
        let allowed = Set([
            "index_find_files",
            "index_list_files",
            "index_search_text",
            "index_read_file",
            "index_search_symbols"
        ])
        return tools.filter { allowed.contains($0.name) }
    }
}
