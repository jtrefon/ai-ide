import Foundation

// MARK: - L2 Application layer — high-level conversation API

/// Single point of entry for the conversation stream. All producers (user,
/// agent, tools, planner, system) **emit** through this service; they never
/// mutate the log directly. Facade behind the full pipeline.
///
/// Implemented by `ConversationCoordinator`. The app/pipeline/UI depend on
/// this protocol (Dependency Inversion) — the concrete coordinator is
/// wired via `DependencyContainer`.
public protocol ConversationService: Sendable {

    // ── Session lifecycle ──────────────────────────────────────────

    /// Start a brand-new session with the given identifier.
    func startSession(_ sessionId: String) async

    /// Switch to an existing session without altering any data.
    func switchSession(to sessionId: String) async

    /// Mark a session as closed. The active pointer stays until switched.
    func closeSession(_ sessionId: String) async

    /// The currently active session identifier.
    var currentSessionId: String { get async }

    // ── Turn submission (write) ─────────────────────────────────────

    /// Submit a user message turn.
    func submitUserMessage(_ text: String, sessionId: String) async throws

    /// Commit the agent's (model's) final turn.
    func commitAgentTurn(
        text: String,
        reasoning: String?,
        toolCalls: [ToolCallSummary],
        sessionId: String
    ) async throws

    /// Commit a tool execution result.
    func commitToolResult(
        toolCallId: String,
        name: String,
        status: String,
        targetFile: String?,
        outputRef: String?,
        sessionId: String
    ) async throws

    /// Commit a system-generated message.
    func commitSystemMessage(_ text: String, sessionId: String) async throws

    /// Commit a plan update.
    func commitPlan(_ markdown: String, sessionId: String) async throws

    /// Append a checkpoint (compressed summary). Does **not** mutate
    /// earlier turns.
    func commitCheckpoint(_ summary: String, sessionId: String) async throws

    // ── Read (projections will be built on top in Phase 4) ──────────

    /// All turns for a session, in `seq` order.
    func allTurns(sessionId: String) async -> [Turn]

    /// Turns with `seq > given` for incremental reads.
    func turns(after seq: UInt64, sessionId: String) async -> [Turn]

    // ── Compaction ──────────────────────────────────────────────────

    /// Manually trigger compaction. The coordinator reads the current log,
    /// produces a summary, and appends a `checkpoint` turn. The canonical
    /// log is never edited — only new checkpoint turns are appended.
    func compact(sessionId: String) async throws
}
