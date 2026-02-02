import Combine
import Foundation

@MainActor
final class ChatHistoryCoordinator {
    private let historyManager: ChatHistoryManager
    private var conversationId: String
    private var hasStartedConversation: Bool = false

    init(historyManager: ChatHistoryManager, projectRoot: URL) {
        self.historyManager = historyManager
        self.conversationId = UUID().uuidString
        self.historyManager.setProjectRoot(projectRoot)

        if let persisted = loadPersistedConversationId(projectRoot: projectRoot) {
            conversationId = persisted
            hasStartedConversation = true
        } else {
            persistConversationId(projectRoot: projectRoot, conversationId: conversationId)
        }
    }

    var messages: [ChatMessage] {
        historyManager.messages
    }

    var currentConversationId: String {
        conversationId
    }

    func append(_ message: ChatMessage) {
        historyManager.append(message)
    }

    func upsertToolExecutionMessage(_ message: ChatMessage) {
        historyManager.upsertToolExecutionMessage(message)
    }

    func removeOldestMessages(count: Int) {
        historyManager.removeOldestMessages(count: count)
    }

    func replaceOldestMessages(count: Int, with message: ChatMessage) {
        historyManager.replaceOldestMessages(count: count, with: message)
    }

    func clearConversation() {
        historyManager.clear()
    }

    func updateMessageStatus(toolCallId: String, status: ToolExecutionStatus, content: String? = nil) {
        historyManager.updateMessageStatus(toolCallId: toolCallId, status: status, content: content)
    }

    func startNewConversation(projectRoot: URL) -> (previousConversationId: String, newConversationId: String) {
        let oldConversationId = conversationId
        conversationId = UUID().uuidString
        hasStartedConversation = true
        persistConversationId(projectRoot: projectRoot, conversationId: conversationId)
        historyManager.clear()
        return (oldConversationId, conversationId)
    }

    func updateProjectRoot(
        _ newRoot: URL,
        shouldStartConversationLog: Bool,
        onStartConversation: @escaping @Sendable (
            _ conversationId: String,
            _ mode: String,
            _ projectRootPath: String
        ) async -> Void
    ) {
        historyManager.setProjectRoot(newRoot)

        if let persisted = loadPersistedConversationId(projectRoot: newRoot) {
            conversationId = persisted
            hasStartedConversation = true
        } else {
            persistConversationId(projectRoot: newRoot, conversationId: conversationId)
        }

        if shouldStartConversationLog, !hasStartedConversation {
            hasStartedConversation = true
            Task.detached(priority: .utility) {
                await onStartConversation(self.conversationId, "", newRoot.path)
            }
        }
    }

    private func conversationIdFileURL(projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("conversation_id.txt")
    }

    private func loadPersistedConversationId(projectRoot: URL) -> String? {
        let url = conversationIdFileURL(projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func persistConversationId(projectRoot: URL, conversationId: String) {
        let url = conversationIdFileURL(projectRoot: projectRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? conversationId.write(to: url, atomically: true, encoding: .utf8)
    }
}
