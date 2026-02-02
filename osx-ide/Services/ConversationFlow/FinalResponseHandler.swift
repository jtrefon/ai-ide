import Foundation

@MainActor
final class FinalResponseHandler {
    private let historyCoordinator: ChatHistoryCoordinator
    private let aiInteractionCoordinator: AIInteractionCoordinator

    init(
        historyCoordinator: ChatHistoryCoordinator,
        aiInteractionCoordinator: AIInteractionCoordinator
    ) {
        self.historyCoordinator = historyCoordinator
        self.aiInteractionCoordinator = aiInteractionCoordinator
    }

    func requestFinalResponseIfNeeded(
        response: AIServiceResponse,
        explicitContext: String?,
        projectRoot: URL,
        toolResults: [ChatMessage]
    ) async throws -> AIServiceResponse {
        let draft = response.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard draft.isEmpty else { return response }

        let toolSummary = toolResultsSummaryText(toolResults)
        let correctionContent: String
        if toolResults.isEmpty {
            correctionContent = "You returned no user-visible response. Provide a final response in plain text now. " +
                "Do not call tools."
        } else {
            correctionContent = "You returned no user-visible response after tool execution. " +
                "Provide a final response in plain text now. Do not call tools.\n\nTool outputs:\n\(toolSummary)"
        }
        let correctionSystem = ChatMessage(
            role: .system,
            content: correctionContent
        )

        let followup = try await aiInteractionCoordinator
            .sendMessageWithRetry(AIInteractionCoordinator.SendMessageWithRetryRequest(
                messages: historyCoordinator.messages + [correctionSystem],
                explicitContext: explicitContext,
                tools: [],
                mode: .chat,
                projectRoot: projectRoot
            ))
            .get()

        let followupContent = followup.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = followupContent?.isEmpty == false
            ? followup.content
            : response.content
        let resolvedContent = (finalContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? finalContent
            : "I wasn't able to generate a final response. " +
                "Here is a summary of tool outputs:\n\n\(toolSummary)\n\n" +
                "Please retry or clarify the next step."
        return AIServiceResponse(content: resolvedContent, toolCalls: nil)
    }

    func appendFinalMessageAndLog(response: AIServiceResponse, conversationId: String) {
        let splitFinal = ChatPromptBuilder.splitReasoning(from: response.content ?? "No response received.")
        let trimmedContent = splitFinal.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent = trimmedContent.isEmpty
            ? "Assistant returned no user-visible response. Please retry or rephrase."
            : splitFinal.content
        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: response.content ?? "")
        let deliveryStatusText: String
        switch deliveryStatus {
        case .done:
            deliveryStatusText = "done"
        case .needsWork:
            deliveryStatusText = "needs_work"
        case .none:
            deliveryStatusText = "missing"
        }
        historyCoordinator.append(
            ChatMessage(
                role: .assistant,
                content: displayContent,
                context: ChatMessageContentContext(reasoning: splitFinal.reasoning)
            )
        )

        let hasReasoning = (splitFinal.reasoning?.isEmpty == false)
        let contentLength = displayContent.count
        let reasoningText = splitFinal.reasoning

        Task.detached(priority: .utility) {
            await AppLogger.shared.info(
                category: .conversation,
                message: "chat.assistant_message",
                context: AppLogger.LogCallContext(metadata: [
                    "conversationId": conversationId,
                    "contentLength": contentLength,
                    "hasReasoning": hasReasoning,
                    "deliveryStatus": deliveryStatusText
                ])
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.assistant_message",
                data: [
                    "content": displayContent,
                    "reasoning": reasoningText as Any,
                    "deliveryStatus": deliveryStatusText
                ]
            )
        }
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
}
