import Foundation

extension AIToolExecutor {
    func logToolExecuteStart(
        conversationId: String?,
        toolCall: AIToolCall,
        targetFile: String?
    ) async {
        await AppLogger.shared.info(category: .tool, message: "tool.execute_start", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "targetPath": targetFile as Any
        ])

        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_start",
                data: [
                    "targetPath": targetFile as Any
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.execute_start",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id,
                    "targetPath": targetFile as Any
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.execute_start", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "targetPath": targetFile as Any,
            "argumentKeys": Array(toolCall.arguments.keys).sorted()
        ])
    }

    func logToolExecuteProgress(
        conversationId: String?,
        toolName: String,
        toolCallId: String,
        chunk: String,
        totalLength: Int
    ) async {
        let cappedChunk = String(chunk.suffix(16_384))
        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCallId,
                type: "tool.execute_progress",
                data: [
                    "chunk": cappedChunk,
                    "chunkLength": chunk.count,
                    "totalLength": totalLength
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolName)
            )
        )
    }

    func logToolExecuteSuccess(conversationId: String?, toolCall: AIToolCall, resultLength: Int) async {
        await AppLogger.shared.info(category: .tool, message: "tool.execute_success", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "resultLength": resultLength
        ])

        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_success",
                data: [
                    "resultLength": resultLength
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.execute_success",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id,
                    "resultLength": resultLength
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.execute_success", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "resultLength": resultLength
        ])
    }

    func logToolExecuteError(conversationId: String?, toolCall: AIToolCall, error: Error) async {
        await AppLogger.shared.error(category: .tool, message: "tool.execute_error", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "error": error.localizedDescription
        ])

        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_error",
                data: [
                    "error": error.localizedDescription
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.execute_error",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id,
                    "error": error.localizedDescription
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.execute_error", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id,
            "error": error.localizedDescription
        ])
    }

    func logToolNotFound(conversationId: String?, toolCall: AIToolCall) async {
        await AppLogger.shared.error(category: .tool, message: "tool.not_found", metadata: [
            "conversationId": conversationId as Any,
            "tool": toolCall.name,
            "toolCallId": toolCall.id
        ])

        if let conversationId {
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "tool.not_found",
                data: [
                    "tool": toolCall.name,
                    "toolCallId": toolCall.id
                ]
            )
        }

        await AIToolTraceLogger.shared.log(type: "tool.not_found", data: [
            "tool": toolCall.name,
            "toolCallId": toolCall.id
        ])
    }

    nonisolated static func formatError(_ error: Error, toolName: String) -> String {
        if toolName == "index_read_file" {
            let msg = error.localizedDescription
            if msg.lowercased().hasPrefix("file not found") {
                return "Error: \(msg)\n\nHint: do not guess filenames. First use index_find_files(query: \"RegistrationPage\") or index_list_files(query: \"registration-app/src\") to discover the correct path, then call index_read_file with that exact path."
            }
        }
        return "Error: \(error.localizedDescription)"
    }
}
