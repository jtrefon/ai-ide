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
    
    /// Creates a signature for a tool call to identify duplicates
    private static func toolCallSignature(_ toolCall: AIToolCall) -> String {
        let argsSignature = toolCall.arguments.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(toolCall.name):\(argsSignature)"
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
        var normalized = content.lowercased()
        
        // Remove reasoning blocks
        normalized = normalized.replacingOccurrences(of: "<ide_reasoning>.*?</ide_reasoning>", with: "", options: .regularExpression)
        
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
