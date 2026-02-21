import Foundation

extension AIToolExecutor {
    func logToolExecuteStart(
        conversationId: String?,
        toolCall: AIToolCall,
        targetFile: String?
    ) async {
        await AppLogger.shared.info(
            category: .tool,
            message: "tool.execute_start",
            context: AppLogger.LogCallContext(metadata: [
                "conversationId": conversationId as Any,
                "tool": toolCall.name,
                "toolCallId": toolCall.id,
                "targetPath": targetFile as Any
            ])
        )

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
        toolCall: AIToolCall,
        chunk: String,
        totalLength: Int
    ) async {
        let cappedChunk = String(chunk.suffix(16_384))
        await ExecutionLogStore.shared.append(
            ExecutionLogAppendRequest(
                toolCallId: toolCall.id,
                type: "tool.execute_progress",
                data: [
                    "chunk": cappedChunk,
                    "chunkLength": chunk.count,
                    "totalLength": totalLength
                ],
                context: ExecutionLogContext(conversationId: conversationId, tool: toolCall.name)
            )
        )
    }

    func logToolExecuteSuccess(conversationId: String?, toolCall: AIToolCall, resultLength: Int) async {
        await AppLogger.shared.info(
            category: .tool,
            message: "tool.execute_success",
            context: AppLogger.LogCallContext(metadata: [
                "conversationId": conversationId as Any,
                "tool": toolCall.name,
                "toolCallId": toolCall.id,
                "resultLength": resultLength
            ])
        )

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
        await AppLogger.shared.error(
            category: .tool,
            message: "tool.execute_error",
            context: AppLogger.LogCallContext(metadata: [
                "conversationId": conversationId as Any,
                "tool": toolCall.name,
                "toolCallId": toolCall.id,
                "error": error.localizedDescription
            ])
        )

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
        await AppLogger.shared.error(
            category: .tool,
            message: "tool.not_found",
            context: AppLogger.LogCallContext(metadata: [
                "conversationId": conversationId as Any,
                "tool": toolCall.name,
                "toolCallId": toolCall.id
            ])
        )

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
        if let timeoutError = error as? ToolExecutionTimedOutError {
            return [
                "Error: Tool execution timed out after \(timeoutError.timeoutSeconds)s.",
                "",
                "IMPORTANT: This tool was terminated for safety to prevent the agent from getting stuck.",
                "This usually means the command/tool did not return control (e.g. started a long-running process, waited for user input, or tailed logs).",
                "",
                "Recovery instructions (do NOT repeat the same call unchanged):",
                "- Use a different approach that completes quickly or produces incremental output.",
                "- Avoid non-terminating commands (dev servers/watchers, \"tail -f\", interactive prompts).",
                "- Prefer non-interactive flags (e.g. --yes, --no-prompt, --non-interactive) and bounded output (e.g. head, sed, grep with limits).",
                "- For npm operations (install, build, create vite), you MUST add \"timeout_seconds\": 600 or higher.",
                "- If re-running a shell command, make it explicitly finite (e.g. add a max count, filter scope, or only run the build/test target you need).",
                "- Example: {\"command\": \"npm install\", \"timeout_seconds\": 600}"
            ].joined(separator: "\n")
        }

        if error is ToolExecutionCancelledError {
            return [
                "Error: Tool execution cancelled.",
                "",
                "IMPORTANT: The tool was stopped intentionally (user action or protective cancellation).",
                "Assume the previous approach risked hanging or was no longer desired.",
                "",
                "Recovery instructions (do NOT repeat the same call unchanged):",
                "- Choose a safer, non-blocking alternative that returns control.",
                "- If the task requires execution, prefer short commands that terminate (build/test/format), not long-running servers/watchers."
            ].joined(separator: "\n")
        }
        
        // Check for missing argument errors
        let errorMessage = error.localizedDescription.lowercased()
        if errorMessage.contains("missing") || errorMessage.contains("required") || errorMessage.contains("argument") {
            return formatMissingArgumentError(error: error, toolName: toolName)
        }

        if toolName == "index_read_file" {
            let msg = error.localizedDescription
            if msg.lowercased().hasPrefix("file not found") {
                return "Error: \(msg)\n\nHint: do not guess filenames. " +
                    "First use index_find_files(query: \"RegistrationPage\") or index_list_files(query: \"registration-app/src\") " +
                    "to discover the correct path, then call index_read_file with that exact path."
            }
        }
        return "Error: \(error.localizedDescription)"
    }
    
    nonisolated private static func formatMissingArgumentError(error: Error, toolName: String) -> String {
        let errorMsg = error.localizedDescription
        
        // Provide specific guidance based on the tool and missing argument
        switch toolName {
        case "write_files":
            return [
                "Error: \(errorMsg)",
                "",
                "The write_files tool requires a 'files' argument containing an array of file objects.",
                "Each file object should have:",
                "  - 'path': The relative path of the file (e.g., 'src/App.js')",
                "  - 'content': The file content as a string",
                "",
                "Example correct call:",
                "{\"files\": [{\"path\": \"src/App.js\", \"content\": \"...\"}]}",
                "",
                "Common mistakes:",
                "- Passing 'content' instead of 'files'",
                "- Passing a single file object instead of an array",
                "- Missing the 'path' or 'content' fields in each file object"
            ].joined(separator: "\n")
            
        case "write_file", "create_file":
            return [
                "Error: \(errorMsg)",
                "",
                "The \(toolName) tool requires:",
                "  - 'path': The relative path of the file to write",
                "  - 'content': The file content as a string",
                "",
                "Example correct call:",
                "{\"path\": \"src/App.js\", \"content\": \"...\"}"
            ].joined(separator: "\n")
            
        case "run_command":
            return [
                "Error: \(errorMsg)",
                "",
                "The run_command tool requires:",
                "  - 'command': The shell command to execute (required)",
                "",
                "Optional arguments:",
                "  - 'working_directory': The directory to run the command in",
                "  - 'timeout_seconds': Timeout in seconds (1-600, default 120)",
                "",
                "IMPORTANT: For npm install, npm create vite, npm build, or any long-running command,",
                "you MUST set timeout_seconds to at least 300 (5 minutes) or 600 (10 minutes).",
                "",
                "Example for npm install:",
                "{\"command\": \"npm install\", \"timeout_seconds\": 600, \"working_directory\": \"./my-project\"}"
            ].joined(separator: "\n")
            
        case "replace_in_file":
            return [
                "Error: \(errorMsg)",
                "",
                "The replace_in_file tool requires:",
                "  - 'path': The file path to modify",
                "  - 'old_text': The exact text to find and replace",
                "  - 'new_text': The replacement text",
                "",
                "Example correct call:",
                "{\"path\": \"src/App.js\", \"old_text\": \"const a = 1\", \"new_text\": \"const a = 2\"}"
            ].joined(separator: "\n")
            
        default:
            return [
                "Error: \(errorMsg)",
                "",
                "The tool call is missing required arguments. Please check the tool schema",
                "and ensure all required fields are provided with correct types.",
                "",
                "Review the tool definition to see required vs optional arguments."
            ].joined(separator: "\n")
        }
    }
}
