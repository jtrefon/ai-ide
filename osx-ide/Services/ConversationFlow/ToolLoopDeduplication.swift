//
//  ToolLoopDeduplication.swift
//  osx-ide
//
//  Tool deduplication logic for the tool loop handler
//

import Foundation

/// Handles tool call deduplication and batch analysis
@MainActor
struct ToolLoopDeduplication {
    
    /// Deduplicates tool calls within a single batch
    static func deduplicateToolCalls(_ toolCalls: [AIToolCall]) -> [AIToolCall] {
        var seenSignatures: Set<String> = []
        var uniqueCalls: [AIToolCall] = []
        
        for call in toolCalls {
            let signature = toolCallSignature(call)
            if !seenSignatures.contains(signature) {
                seenSignatures.insert(signature)
                uniqueCalls.append(call)
            }
        }
        
        return uniqueCalls
    }
    
    /// Creates a signature for a tool call to identify duplicates.
    /// Excludes metadata arguments (_tool_call_id, _conversation_id) so that
    /// repeated attempts on the same path are detected as duplicates.
    private static func toolCallSignature(_ toolCall: AIToolCall) -> String {
        let metadataKeys: Set<String> = ["_tool_call_id", "_conversation_id", "_run_id"]
        let argsSignature = toolCall.arguments
            .filter { !metadataKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(toolCall.name):\(argsSignature)"
    }

    /// Creates a path-based signature for detecting repeated failed file access attempts.
    /// This is separate from the full tool signature to catch the model trying
    /// different tools on the same non-existent path.
    static func toolPathSignature(_ toolCall: AIToolCall) -> String? {
        let pathKeys = ["path", "filePath", "targetPath", "file_path", "target"]
        for key in pathKeys {
            if let path = toolCall.arguments[key] as? String {
                return "\(toolCall.name):\(path)"
            }
        }
        return nil
    }
    
    /// Creates a signature for a batch of tool calls to detect repeated batches
    static func toolBatchSignature(_ toolCalls: [AIToolCall]) -> String {
        let sortedCalls = toolCalls.sorted { $0.name < $1.name }
        return sortedCalls.map { toolCallSignature($0) }.joined(separator: "|")
    }
    
    /// Normalizes content for detecting repeated responses without tool calls
    static func normalizedNoToolCallContentSignature(_ content: String?) -> String {
        guard let content = content, !content.isEmpty else {
            return "empty"
        }
        
        // Remove common patterns that don't affect the semantic meaning
        var normalized = ChatPromptBuilder.contentForDisplay(from: content).lowercased()
        
        // Remove common filler phrases
        let fillerPhrases = [
            "i understand",
            "let me help",
            "i'll help",
            "here's what i'll do",
            "i will",
            "let me",
            "i can",
            "i'm going to"
        ]
        
        for phrase in fillerPhrases {
            normalized = normalized.replacingOccurrences(of: phrase, with: "")
        }
        
        // Normalize whitespace
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return normalized.isEmpty ? "empty" : String(normalized.prefix(200))
    }
    
    /// Checks if tool calls are read-only (information gathering only)
    static func areReadOnlyToolCalls(_ toolCalls: [AIToolCall]) -> Bool {
        let readOnlyToolNames = [
            "read_file",
            "list_files", 
            "search_files",
            "get_file_info",
            "check_file_exists",
            "conversation_fold",
            "checkpoint_list"
        ]
        
        return toolCalls.allSatisfy { call in
            readOnlyToolNames.contains(call.name)
        }
    }
    
    /// Creates a signature for read-only tool batches
    static func readOnlyToolBatchSignature(_ toolCalls: [AIToolCall]) -> String {
        let readOnlyCalls = toolCalls.filter { call in
            ["read_file", "list_files", "search_files", "conversation_fold", "checkpoint_list"].contains(call.name)
        }
        return toolBatchSignature(readOnlyCalls)
    }
}
