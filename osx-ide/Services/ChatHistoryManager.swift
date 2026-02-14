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
    private static let defaultGreetingMessage = "Hello! I'm your AI coding assistant. How can I help you today?"
    private var saveTask: Task<Void, Never>?

    public init() {
        ensureDefaultGreetingMessageIfNeeded()
    }

    private func ensureDefaultGreetingMessageIfNeeded() {
        guard messages.isEmpty else { return }
        messages.append(
            ChatMessage(
                role: .assistant,
                content: Self.defaultGreetingMessage
            )
        )
    }

    public func setProjectRoot(_ root: URL) {
        projectRoot = root
        loadHistory()
        ensureDefaultGreetingMessageIfNeeded()
    }

    public func append(_ message: ChatMessage) {
        // Don't filter draft messages - they should always be visible during streaming
        if !message.isDraft && ChatMessageVisibilityPolicy.isEmptyAssistantMessage(message) {
            return
        }

        messages.append(message)
        saveHistoryAsync()
    }

    public func upsertToolExecutionMessage(_ message: ChatMessage) {
        guard message.isToolExecution, let toolCallId = message.toolCallId, !toolCallId.isEmpty else {
            append(message)
            return
        }

        if let index = messages.lastIndex(where: { $0.toolCallId == toolCallId }) {
            messages[index] = message
            saveHistoryAsync()
        } else {
            append(message)
        }
    }

    public func upsertMessage(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            saveHistoryAsync()
        } else {
            append(message)
        }
    }
    
    /// Finalizes a draft message by converting it to a regular message with content
    public func finalizeDraftMessage(id: UUID, content: String, reasoning: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let oldMessage = messages[index]
        messages[index] = ChatMessage(
            id: oldMessage.id,
            role: oldMessage.role,
            content: content,
            timestamp: oldMessage.timestamp,
            context: ChatMessageContentContext(reasoning: reasoning, codeContext: oldMessage.codeContext),
            tool: ChatMessageToolContext(
                toolName: oldMessage.toolName,
                toolStatus: oldMessage.toolStatus,
                target: ToolInvocationTarget(targetFile: oldMessage.targetFile, toolCallId: oldMessage.toolCallId),
                toolCalls: oldMessage.toolCalls ?? []
            ),
            isDraft: false
        )
        saveHistoryAsync()
    }
    
    /// Removes a draft message by ID (used when operation is cancelled or fails)
    public func removeDraftMessage(id: UUID) {
        messages.removeAll { $0.id == id && $0.isDraft }
        saveHistoryAsync()
    }
    
    /// Gets a draft message by ID
    public func getDraftMessage(id: UUID) -> ChatMessage? {
        messages.first { $0.id == id && $0.isDraft }
    }

    public func replaceMessage(at index: Int, with message: ChatMessage) {
        guard messages.indices.contains(index) else { return }
        messages[index] = message
        saveHistoryAsync()
    }

    public func removeLast() {
        if !messages.isEmpty {
            messages.removeLast()
            saveHistoryAsync()
        }
    }

    public func removeOldestMessages(count: Int) {
        guard count > 0 else { return }
        guard !messages.isEmpty else { return }

        if count >= messages.count {
            messages.removeAll()
        } else {
            messages.removeFirst(count)
        }

        ensureDefaultGreetingMessageIfNeeded()
        saveHistoryAsync()
    }

    public func replaceOldestMessages(count: Int, with message: ChatMessage) {
        guard count > 0 else { return }
        guard !messages.isEmpty else { return }

        if count >= messages.count {
            messages.removeAll()
        } else {
            messages.removeFirst(count)
        }

        messages.insert(message, at: 0)
        ensureDefaultGreetingMessageIfNeeded()
        saveHistoryAsync()
    }

    public func clear() {
        messages.removeAll()
        messages.append(ChatMessage(
            role: .assistant,
            content: "Conversation cleared. How can I assist you now?"
        ))
        saveHistoryAsync()
    }

    public func updateMessageStatus(toolCallId: String, status: ToolExecutionStatus, content: String? = nil) {
        if let index = messages.lastIndex(where: { $0.toolCallId == toolCallId }) {
            let oldMessage = messages[index]
            messages[index] = ChatMessage(
                role: oldMessage.role,
                content: content ?? oldMessage.content,
                context: ChatMessageContentContext(
                    reasoning: oldMessage.reasoning,
                    codeContext: oldMessage.codeContext
                ),
                tool: ChatMessageToolContext(
                    toolName: oldMessage.toolName,
                    toolStatus: status,
                    target: ToolInvocationTarget(targetFile: oldMessage.targetFile, toolCallId: oldMessage.toolCallId),
                    toolCalls: oldMessage.toolCalls ?? []
                )
            )
            saveHistoryAsync()
        }
    }

    /// Saves history asynchronously with debouncing to avoid blocking the main thread
    public func saveHistoryAsync() {
        // Cancel any pending save task
        saveTask?.cancel()
        
        // Schedule a new save with a small delay for debouncing
        saveTask = Task.detached(priority: .utility) { [weak self] in
            // Small delay for debouncing
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            
            guard !Task.isCancelled else { return }
            
            await self?.performSave()
        }
    }
    
    /// Synchronous save for cases where we need to ensure data is persisted
    public func saveHistory() {
        guard let url = historyFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(messages)
            try ensureDirectoryExists(for: url)
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } catch {
            Task {
                await CrashReporter.shared.capture(
                    error,
                    context: CrashReportContext(operation: "ChatHistoryManager.saveHistory"),
                    metadata: ["url": url.path],
                    file: #fileID,
                    function: #function,
                    line: #line
                )
            }
        }
    }
    
    private func performSave() async {
        guard let url = historyFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(messages)
            try ensureDirectoryExists(for: url)
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } catch {
            await CrashReporter.shared.capture(
                error,
                context: CrashReportContext(operation: "ChatHistoryManager.performSave"),
                metadata: ["url": url.path],
                file: #fileID,
                function: #function,
                line: #line
            )
        }
    }

    private func loadHistory() {
        guard let url = historyFileURL() else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            Task {
                await CrashReporter.shared.capture(
                    error,
                    context: CrashReportContext(operation: "ChatHistoryManager.loadHistory"),
                    metadata: ["url": url.path],
                    file: #fileID,
                    function: #function,
                    line: #line
                )
            }
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
