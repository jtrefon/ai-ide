import Foundation

enum MessageTruncationPolicy {
    static let maxToolResultCharacters = ToolLoopConstants.maxToolResultCharacters
    static let maxTotalMessageCharacters = ToolLoopConstants.maxTotalMessageCharacters
    private static let truncationSuffix = "\n... [truncated]"

    static func truncateForModel(_ messages: [ChatMessage]) -> [ChatMessage] {
        var truncated = messages.map(truncateToolResult)
        truncated = enforceCharacterBudget(truncated)
        return truncated
    }

    private static func truncateToolResult(_ message: ChatMessage) -> ChatMessage {
        guard message.role == .tool || message.isToolExecution else { return message }
        guard message.content.count > maxToolResultCharacters else { return message }

        let trimmed = String(message.content.prefix(maxToolResultCharacters)) + truncationSuffix
        return ChatMessage(
            id: message.id,
            role: message.role,
            content: trimmed,
            timestamp: message.timestamp,
            context: ChatMessageContentContext(reasoning: message.reasoning, codeContext: message.codeContext),
            tool: ChatMessageToolContext(
                toolName: message.toolName,
                toolStatus: message.toolStatus,
                target: ToolInvocationTarget(targetFile: message.targetFile, toolCallId: message.toolCallId),
                toolCalls: message.toolCalls ?? []
            ),
            isDraft: message.isDraft
        )
    }

    private static func enforceCharacterBudget(_ messages: [ChatMessage]) -> [ChatMessage] {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        guard totalChars > maxTotalMessageCharacters else { return messages }

        var result = messages
        var currentTotal = totalChars

        for index in result.indices where currentTotal > maxTotalMessageCharacters {
            let msg = result[index]
            guard msg.role == .tool || msg.isToolExecution else { continue }
            guard msg.content.count > ToolLoopConstants.toolResultContentLimit else { continue }

            let allowance = ToolLoopConstants.toolResultBudgetAllowance
            let trimmed = String(msg.content.prefix(allowance)) + truncationSuffix
            currentTotal -= (msg.content.count - trimmed.count)
            result[index] = ChatMessage(
                id: msg.id,
                role: msg.role,
                content: trimmed,
                timestamp: msg.timestamp,
                context: ChatMessageContentContext(reasoning: msg.reasoning, codeContext: msg.codeContext),
                tool: ChatMessageToolContext(
                    toolName: msg.toolName,
                    toolStatus: msg.toolStatus,
                    target: ToolInvocationTarget(targetFile: msg.targetFile, toolCallId: msg.toolCallId),
                    toolCalls: msg.toolCalls ?? []
                ),
                isDraft: msg.isDraft
            )
        }
        return result
    }
}

// MARK: - Recoverable tool-output archiving (Context Access Layer, L0/L1)

/// Persists the full text of an overflowing tool result so truncation becomes
/// *recoverable*: the model receives a preview plus a path it can re-read. The
/// `read` tool is sandboxed to the project, so the path must live under
/// `<root>/.ide/tool-output` when a project root is available.
enum ToolOutputArchive {
    /// Window-aware cap for a single tool result sent to the model.
    /// Large-window / sliding-window models have ample headroom, so we permit a
    /// generous character budget (≈ window size in tokens × 4) instead of the old
    /// flat 12k cap — this is what eliminates the re-read storm. Smaller/compaction
    /// models fall back to a proportional cap floored at a sane minimum.
    static func effectiveToolOutputLimit(modelID: String) -> Int {
        let profile = ModelContextProfile.profile(for: modelID)
        if profile.defaultStrategy == .slidingWindow, profile.windowSize >= 128_000 {
            return profile.windowSize * 4
        }
        return max(12_000, profile.windowSize / 8)
    }

    @discardableResult
    static func offload(toolCallId: String, full: String, projectRoot: URL?) -> String {
        let dir: URL
        if let projectRoot {
            dir = projectRoot
                .appendingPathComponent(AppConstantsFileSystem.projectDirName)
                .appendingPathComponent("tool-output")
        } else {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("osx-ide-tool-output")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(toolCallId).txt")
        try? full.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }
}
