import Foundation

/// Shared utility functions for tool loop processing across handlers.
/// This eliminates code duplication between ToolLoopHandler, QAReviewHandler,
/// FinalResponseHandler, and ConversationSendCoordinator.
enum ToolLoopUtilities {
    private static func prompt(
        key: String,
        projectRoot: URL,
        replacements: [String: String] = [:]
    ) throws -> String {
        var content = try PromptRepository.shared.prompt(
            key: key,
            projectRoot: projectRoot
        )
        for (token, value) in replacements {
            content = content.replacingOccurrences(of: token, with: value)
        }
        return content
    }

    private static func planSection(from plan: String) -> String {
        let trimmedPlan = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlan.isEmpty else { return "" }
        return "Plan:\n\(trimmedPlan)"
    }

    private static func nextPendingSection(from planMarkdown: String) -> String {
        guard let nextPendingLine = planMarkdown
            .components(separatedBy: .newlines)
            .first(where: { $0.contains("- [ ]") })?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !nextPendingLine.isEmpty else {
            return ""
        }
        return "Next unfinished item:\n\(nextPendingLine)"
    }

    // MARK: - Text Processing
    
    /// Truncates text to a specified limit with a truncation marker.
    /// - Parameters:
    ///   - text: The text to truncate
    ///   - limit: Maximum character limit
    /// - Returns: Truncated text with "[TRUNCATED]" marker if needed
    static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head = text.prefix(limit)
        return String(head) + "\n\n[TRUNCATED]"
    }
    
    // MARK: - Tool Output Processing
    
    /// Extracts the relevant text from a tool message.
    /// Handles both regular messages and tool execution envelopes.
    /// - Parameter message: The chat message to extract text from
    /// - Returns: The relevant text content
    static func toolOutputText(from message: ChatMessage) -> String {
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
    
    /// Builds a summary text from tool results.
    /// - Parameter toolResults: Array of tool result messages
    /// - Returns: Formatted summary string
    static func toolResultsSummaryText(_ toolResults: [ChatMessage]) -> String {
        let lines = toolResults.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let status = message.toolStatus?.rawValue ?? "unknown"
            let preview = truncate(toolOutputText(from: message), limit: ToolLoopConstants.toolResultPreviewLimit)
            return "- \(message.toolName ?? "unknown_tool") (\(toolCallId)) [\(status)]: \(preview)"
        }
        return lines.isEmpty ? "No tool outputs." : lines.joined(separator: "\n")
    }
    
    // MARK: - Snapshot Building
    
    /// Creates tool call summaries for orchestration snapshots.
    /// - Parameter toolCalls: Array of tool calls to summarize
    /// - Returns: Array of tool call summaries
    static func toolCallSummaries(_ toolCalls: [AIToolCall]) -> [OrchestrationRunSnapshot.ToolCallSummary] {
        toolCalls.map {
            OrchestrationRunSnapshot.ToolCallSummary(
                id: $0.id,
                name: $0.name,
                argumentKeys: Array($0.arguments.keys).sorted()
            )
        }
    }
    
    /// Creates tool result summaries for orchestration snapshots.
    /// - Parameter toolResults: Array of tool result messages
    /// - Returns: Array of tool result summaries
    static func toolResultSummaries(_ toolResults: [ChatMessage]) -> [OrchestrationRunSnapshot.ToolResultSummary] {
        toolResults.compactMap { message in
            guard let toolCallId = message.toolCallId else { return nil }
            let output = toolOutputText(from: message)
            return OrchestrationRunSnapshot.ToolResultSummary(
                toolCallId: toolCallId,
                toolName: message.toolName ?? "unknown_tool",
                status: message.toolStatus?.rawValue ?? "unknown",
                targetFile: message.targetFile,
                outputPreview: truncate(output, limit: ToolLoopConstants.toolOutputSnapshotLimit)
            )
        }
    }
    
    /// Extracts failure reasons from tool results.
    /// - Parameter toolResults: Array of tool result messages
    /// - Returns: Failure summary string if any failures exist
    static func failureReason(from toolResults: [ChatMessage]) -> String? {
        let failures = toolResults.filter { $0.isToolExecution && $0.toolStatus == .failed }
        guard !failures.isEmpty else { return nil }
        let summary = failures.compactMap { message -> String? in
            guard let toolCallId = message.toolCallId else { return nil }
            let preview = truncate(toolOutputText(from: message), limit: ToolLoopConstants.failurePreviewLimit)
            return "\(message.toolName ?? "unknown_tool") (\(toolCallId)): \(preview)"
        }
        return summary.joined(separator: "\n")
    }

    private static func focusedConversationContextSection(from historyMessages: [ChatMessage]) -> String {
        let recentMessages = historyMessages
            .filter { !$0.isDraft }
            .suffix(16)

        let recentConversationLines = recentMessages.compactMap { message -> String? in
            guard !message.isToolExecution else { return nil }
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let roleLabel: String
            switch message.role {
            case .user:
                roleLabel = "User"
            case .assistant:
                roleLabel = "Assistant"
            case .system:
                roleLabel = "System"
            case .tool:
                roleLabel = "Tool"
            }

            return "- \(roleLabel): \(truncate(trimmed, limit: 220))"
        }

        let recentToolLines = recentMessages.compactMap { message -> String? in
            guard message.isToolExecution else { return nil }
            let status = message.toolStatus?.rawValue ?? "unknown"
            let toolName = message.toolName ?? "unknown_tool"
            let toolOutput = toolOutputText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
            let compactOutput = toolOutput.isEmpty ? "No output recorded." : truncate(toolOutput, limit: 220)
            return "- \(toolName) [\(status)]: \(compactOutput)"
        }

        var sections: [String] = []
        if !recentConversationLines.isEmpty {
            sections.append("Recent conversation:\n" + recentConversationLines.joined(separator: "\n"))
        }
        if !recentToolLines.isEmpty {
            sections.append("Recent tool execution results:\n" + recentToolLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    static func buildFocusedExecutionMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        historyMessages: [ChatMessage]
    ) async throws -> [ChatMessage] {
        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        let plan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let contextSection = focusedConversationContextSection(from: historyMessages)

        var parts: [String] = [
            try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                projectRoot: projectRoot
            )
        ]

        if !contextSection.isEmpty {
            parts.append(contextSection)
        }

        if !plan.isEmpty {
            parts.append("Plan:\n\(plan)")
        }

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    static func buildStalledExecutionTransitionMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        toolSummary: String
    ) async throws -> [ChatMessage] {
        let plan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let parts: [String] = [
            try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                projectRoot: projectRoot
            ),
            try prompt(
                key: "ConversationFlow/Corrections/stalled_execution_transition",
                projectRoot: projectRoot,
                replacements: [
                    "{{TOOL_SUMMARY}}": toolSummary,
                    "{{PLAN_SECTION}}": planSection(from: plan)
                ]
            )
        ]

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    static func buildAutonomousNoUserInputMessages(
        userInput: String,
        conversationId: String?,
        projectRoot: URL,
        existingAssistantContent: String,
        toolsAvailable: Bool
    ) async throws -> [ChatMessage] {
        let plan: String
        if let conversationId {
            plan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        } else {
            plan = ""
        }

        var parts: [String] = []
        if toolsAvailable {
            parts.append(try prompt(
                key: "ConversationFlow/Corrections/autonomous_with_tools",
                projectRoot: projectRoot,
                replacements: [
                    "{{ASSISTANT_DRAFT}}": existingAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    "{{PLAN_SECTION}}": planSection(from: plan)
                ]
            ))
        } else {
            parts.append(try prompt(
                key: "ConversationFlow/Corrections/autonomous_without_tools",
                projectRoot: projectRoot,
                replacements: [
                    "{{ASSISTANT_DRAFT}}": existingAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    "{{PLAN_SECTION}}": planSection(from: plan)
                ]
            ))
        }

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    static func buildRepeatedSignatureDiversionMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        repeatedSignatures: [String]
    ) async throws -> [ChatMessage] {
        let plan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""

        let parts: [String] = [
            try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                projectRoot: projectRoot
            ),
            try prompt(
                key: "ConversationFlow/Corrections/repeated_signature_diversion",
                projectRoot: projectRoot,
                replacements: [
                    "{{REPEATED_SIGNATURES}}": repeatedSignatures.map { "- \($0)" }.joined(separator: "\n"),
                    "{{PLAN_SECTION}}": planSection(from: plan)
                ]
            )
        ]

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    static func buildRepeatedWriteTargetDiversionMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        writeTargetSignature: String
    ) async throws -> [ChatMessage] {
        let plan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""

        let parts: [String] = [
            try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                projectRoot: projectRoot
            ),
            try prompt(
                key: "ConversationFlow/Corrections/repeated_write_target_diversion",
                projectRoot: projectRoot,
                replacements: [
                    "{{WRITE_TARGET_SIGNATURE}}": writeTargetSignature,
                    "{{PLAN_SECTION}}": planSection(from: plan)
                ]
            )
        ]

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    static func buildPlanContinuationMessages(
        userInput: String,
        conversationId: String,
        projectRoot: URL,
        historyMessages: [ChatMessage],
        currentAssistantContent: String,
        planMarkdown: String,
        completedCount: Int,
        totalCount: Int
    ) async throws -> [ChatMessage] {
        let contextSection = focusedConversationContextSection(from: historyMessages)

        var parts: [String] = [
            try PromptRepository.shared.prompt(
                key: "ConversationFlow/Corrections/tool_loop_focused_execution",
                projectRoot: projectRoot
            ),
        ]

        if !contextSection.isEmpty {
            parts.append(contextSection)
        }

        parts.append(try prompt(
                key: "ConversationFlow/Corrections/plan_continuation",
                projectRoot: projectRoot,
                replacements: [
                    "{{COMPLETED_COUNT}}": String(completedCount),
                    "{{TOTAL_COUNT}}": String(totalCount),
                    "{{ASSISTANT_DRAFT}}": currentAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    "{{PLAN_MARKDOWN}}": planMarkdown,
                    "{{NEXT_PENDING_SECTION}}": nextPendingSection(from: planMarkdown)
                ]
            ))

        return [
            ChatMessage(role: .system, content: parts.joined(separator: "\n\n")),
            ChatMessage(role: .user, content: userInput)
        ]
    }

    static func buildStalledFinalResponseMessages(
        userInput: String,
        toolSummary: String,
        projectRoot: URL
    ) throws -> [ChatMessage] {
        let systemContent = try PromptRepository.shared.prompt(
            key: "ConversationFlow/Corrections/stalled_final_response_system",
            projectRoot: projectRoot
        )
        let userContent = try prompt(
            key: "ConversationFlow/Corrections/stalled_final_response_user",
            projectRoot: projectRoot,
            replacements: [
                "{{USER_INPUT}}": userInput,
                "{{TOOL_SUMMARY}}": toolSummary
            ]
        )

        return [
            ChatMessage(role: .system, content: systemContent),
            ChatMessage(role: .user, content: userContent)
        ]
    }
    
    // MARK: - Snapshot Persistence
    
    /// Appends a run snapshot to the orchestration store.
    /// - Parameter payload: The snapshot payload to append
    static func appendRunSnapshot(payload: RunSnapshotPayload) async {
        let snapshot = OrchestrationRunSnapshot(
            runId: payload.runId,
            conversationId: payload.conversationId,
            phase: payload.phase,
            iteration: payload.iteration,
            timestamp: Date(),
            userInput: payload.userInput,
            assistantDraft: payload.assistantDraft,
            failureReason: payload.failureReason,
            executionSignals: nil,
            toolCalls: toolCallSummaries(payload.toolCalls),
            toolResults: toolResultSummaries(payload.toolResults)
        )
        try? await OrchestrationRunStore.shared.appendSnapshot(snapshot)
    }
    
    /// Convenience method to append a run snapshot with individual parameters.
    /// - Parameters: Individual snapshot fields
    static func appendRunSnapshot(
        runId: String,
        conversationId: String,
        phase: String,
        iteration: Int?,
        userInput: String,
        assistantDraft: String?,
        failureReason: String?,
        toolCalls: [AIToolCall],
        toolResults: [ChatMessage]
    ) async {
        let payload = RunSnapshotPayload(
            runId: runId,
            conversationId: conversationId,
            phase: phase,
            iteration: iteration,
            userInput: userInput,
            assistantDraft: assistantDraft,
            failureReason: failureReason,
            toolCalls: toolCalls,
            toolResults: toolResults
        )
        await appendRunSnapshot(payload: payload)
    }
}

// MARK: - Run Snapshot Payload

/// Data payload for creating orchestration run snapshots.
struct RunSnapshotPayload {
    let runId: String
    let conversationId: String
    let phase: String
    let iteration: Int?
    let userInput: String
    let assistantDraft: String?
    let failureReason: String?
    let toolCalls: [AIToolCall]
    let toolResults: [ChatMessage]
}
