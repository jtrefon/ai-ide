//
//  ChatHistoryManager.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import SwiftUI

/// Manages the persistence and state of chat messages.
@MainActor
public class ChatHistoryManager: ObservableObject {
    @Published public var messages: [ChatMessage] = []
    private var projectRoot: URL?
    
    public init() {
        if messages.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI coding assistant. How can I help you today?"
            ))
        }
    }

    public func setProjectRoot(_ root: URL) {
        projectRoot = root
        loadHistory()
        if messages.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI coding assistant. How can I help you today?"
            ))
        }
    }
    
    public func append(_ message: ChatMessage) {
        // Skip empty assistant messages at the source
        let isAssistant = message.role == MessageRole.assistant
        let isContentEmpty = message.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        let isReasoningEmpty = (message.reasoning?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ?? true)
        let isToolCallsEmpty = (message.toolCalls?.isEmpty ?? true)
        
        if isAssistant && isContentEmpty && isReasoningEmpty && isToolCallsEmpty {
            return
        }
        
        messages.append(message)
        saveHistory()
    }
    
    public func removeLast() {
        if !messages.isEmpty {
            messages.removeLast()
            saveHistory()
        }
    }
    
    public func clear() {
        messages.removeAll()
        messages.append(ChatMessage(
            role: .assistant,
            content: "Conversation cleared. How can I assist you now?"
        ))
        saveHistory()
    }

    public func updateMessageStatus(toolCallId: String, status: ToolExecutionStatus, content: String? = nil) {
        if let index = messages.lastIndex(where: { $0.toolCallId == toolCallId }) {
            let oldMessage = messages[index]
            messages[index] = ChatMessage(
                role: oldMessage.role,
                content: content ?? oldMessage.content,
                context: ChatMessageContentContext(reasoning: oldMessage.reasoning, codeContext: oldMessage.codeContext),
                tool: ChatMessageToolContext(
                    toolName: oldMessage.toolName,
                    toolStatus: status,
                    target: ToolInvocationTarget(targetFile: oldMessage.targetFile, toolCallId: oldMessage.toolCallId),
                    toolCalls: oldMessage.toolCalls ?? []
                )
            )
            saveHistory()
        }
    }
    
    public func saveHistory() {
        guard let url = historyFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(messages)
            try ensureDirectoryExists(for: url)
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } catch {
            print("Failed to save conversation history: \(error)")
        }
    }
    
    private func loadHistory() {
        guard let url = historyFileURL() else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            print("Failed to load conversation history: \(error)")
        }
    }

    private func historyFileURL() -> URL? {
        guard let projectRoot else { return nil }
        return projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private func ensureDirectoryExists(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
}
