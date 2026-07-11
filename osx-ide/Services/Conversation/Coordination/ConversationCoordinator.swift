import Foundation

// MARK: - L2 Application layer — coordinator (Mediator)

/// The single concrete implementation of `ConversationService`. Acts as a Mediator
/// between producers, the append-only store, and the session registry.
///
/// - Producers **emit** turns through the coordinator (never mutate the log).
/// - The coordinator routes emissions to the correct `ConversationStreamStore`.
/// - Session handling is delegated to the `SessionRegistry`.
/// - Compaction appends a `checkpoint` turn; the canonical log is never edited.
///
/// Thread-safe (actor). The rest of the app depends on `ConversationService`
/// (Dependency Inversion), so the coordinator can be swapped or wrapped.
public actor ConversationCoordinator: ConversationService {

    private let registry: SessionRegistry
    private let compactionThreshold: UInt64  // auto-compact when turn count exceeds this

    public init(
        registry: SessionRegistry,
        compactionThreshold: UInt64 = 50
    ) {
        self.registry = registry
        self.compactionThreshold = compactionThreshold
    }

    // MARK: - Session lifecycle

    public func startSession(_ sessionId: String) async {
        await registry.startNewSession(with: sessionId)
    }

    public func switchSession(to sessionId: String) async {
        await registry.switchSession(to: sessionId)
    }

    public func closeSession(_ sessionId: String) async {
        await registry.closeSession(sessionId)
    }

    public var currentSessionId: String {
        get async {
            await registry.currentSessionId()
        }
    }

    // MARK: - Turn submission

    public func submitUserMessage(_ text: String, sessionId: String) async throws {
        let store = await registry.store(forSessionId: sessionId)
        let event = TurnEvent(
            producer: .user,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .userText(text)
        )
        _ = try await store?.append(event)
        try await autoCompactIfNeeded(sessionId: sessionId)
    }

    public func commitAgentTurn(
        text: String,
        reasoning: String?,
        toolCalls: [ToolCallSummary],
        sessionId: String
    ) async throws {
        let store = await registry.store(forSessionId: sessionId)
        let event = TurnEvent(
            producer: .agent,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .assistant(text: text, reasoning: reasoning, toolCalls: toolCalls)
        )
        _ = try await store?.append(event)
        try await autoCompactIfNeeded(sessionId: sessionId)
    }

    public func commitToolResult(
        toolCallId: String,
        name: String,
        status: String,
        targetFile: String?,
        outputRef: String?,
        sessionId: String
    ) async throws {
        let store = await registry.store(forSessionId: sessionId)
        let summary = ToolResultSummary(
            toolCallId: toolCallId,
            name: name,
            status: status,
            targetFile: targetFile,
            outputRef: outputRef
        )
        let event = TurnEvent(
            producer: .tool,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .toolResult(summary)
        )
        _ = try await store?.append(event)
        try await autoCompactIfNeeded(sessionId: sessionId)
    }

    public func commitSystemMessage(_ text: String, sessionId: String) async throws {
        let store = await registry.store(forSessionId: sessionId)
        let event = TurnEvent(
            producer: .system,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .systemText(text)
        )
        _ = try await store?.append(event)
        try await autoCompactIfNeeded(sessionId: sessionId)
    }

    public func commitPlan(_ markdown: String, sessionId: String) async throws {
        let store = await registry.store(forSessionId: sessionId)
        let event = TurnEvent(
            producer: .planner,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .plan(markdown)
        )
        _ = try await store?.append(event)
        try await autoCompactIfNeeded(sessionId: sessionId)
    }

    public func commitCheckpoint(_ summary: String, sessionId: String) async throws {
        let store = await registry.store(forSessionId: sessionId)
        let event = TurnEvent(
            producer: .system,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .checkpoint(summary)
        )
        _ = try await store?.append(event)
    }

    // MARK: - Read

    public func allTurns(sessionId: String) async -> [Turn] {
        guard let store = await registry.store(forSessionId: sessionId) else { return [] }
        return await store.allTurns()
    }

    public func turns(after seq: UInt64, sessionId: String) async -> [Turn] {
        guard let store = await registry.store(forSessionId: sessionId) else { return [] }
        return await store.turns(after: seq)
    }

    // MARK: - Compaction

    public func compact(sessionId: String) async throws {
        let store = await registry.store(forSessionId: sessionId)
        guard let store else { return }

        let all = await store.allTurns()
        guard !all.isEmpty else { return }

        let userCount = all.filter { if case .userText = $0.content { return true }; return false }.count
        let agentCount = all.filter { if case .assistant = $0.content { return true }; return false }.count
        let toolCount = all.filter { if case .toolResult = $0.content { return true }; return false }.count
        let summary = "checkpoint at seq \(all.last?.meta.seq ?? 0): \(userCount) user, \(agentCount) agent, \(toolCount) tool turns"

        let event = TurnEvent(
            producer: .system,
            sessionId: sessionId,
            conversationId: sessionId,
            content: .checkpoint(summary)
        )
        _ = try await store.append(event)
    }

    // MARK: - Private

    private func autoCompactIfNeeded(sessionId: String) async throws {
        let store = await registry.store(forSessionId: sessionId)
        guard let store else { return }
        let count = await store.allTurns().count
        if UInt64(count) > compactionThreshold {
            try await compact(sessionId: sessionId)
        }
    }
}
