import Combine
import Foundation

/// Metadata envelope for a conversation. Stored alongside the turn chain so we
/// get a traceable UUID id, a UI title (`subject`), and dates — without ever
/// touching the immutable context chain.
public struct ConversationEnvelope: Sendable {
    public let id: UUID
    public var subject: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), subject: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.subject = subject
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The ONLY public API to the conversation context.
///
/// Design invariants (see Documentation/provider-context-caching-research.md):
/// - The **committed chain** (`committed`) is append-only. Nothing may replace,
///   remove, reorder, or edit an existing committed node. This keeps the context
///   trail stable so the provider's prefix cache stays warm.
/// - **System + tool prompts are injected at request time**, never stored in the
///   chain, so they cannot be scrambled (Invariant: protected prefix).
/// - **Drafts and live tool status are ephemeral UI state**, kept OUT of the
///   committed chain. They are composed into `messages` for display only and are
///   never sent to the model.
/// - `compact()` appends a summary checkpoint (append-only); it never edits nodes.
@MainActor
final class ChatHistoryCoordinator: ObservableObject {
    // MARK: - Immutable committed chain (append-only)
    private var committed: [ChatMessage] = []

    // MARK: - Ephemeral UI state (NOT part of the chain)
    private var draft: ChatMessage?
    private var liveToolStatus: [String: ToolExecutionStatus] = [:]
    private var liveToolMessages: [String: ChatMessage] = [:]

    /// Display composition (committed + draft + live tool-status overlay).
    /// SwiftUI observes this. Never contains anything the model shouldn't see
    /// beyond the draft, which is excluded from request messages.
    @Published private(set) var messages: [ChatMessage] = []

    // MARK: - Envelope
    private var envelope: ConversationEnvelope
    var currentConversationId: String { envelope.id.uuidString }
    var conversationEnvelope: ConversationEnvelope { envelope }

    // MARK: - Context strategy
    /// The strategy used to bound the context for the LLM request.
    /// Affects whether `compact()` is called automatically (compaction)
    /// or if the full chain is always sent (slidingWindow).
    var strategy: ContextStrategy = .compaction

    /// Set the strategy from a provider model string (e.g. `"anthropic/claude-sonnet-4-2025..."`).
    /// Uses `ModelContextProfile.profile(for:)` to look up the recommended strategy.
    func updateStrategy(forModel modelID: String) {
        strategy = ModelContextProfile.profile(for: modelID).defaultStrategy
    }

    // MARK: - Init

    init(projectRoot: URL? = nil, envelope: ConversationEnvelope = ConversationEnvelope()) {
        self.envelope = envelope
        recompose()
    }

    // MARK: - Reads

    /// Committed turns only — safe to send to the model. Excludes drafts and
    /// applies no ephemeral overlay (the committed nodes are already final).
    var committedMessages: [ChatMessage] { committed }

    /// Committed turns for the LLM request. If a compaction checkpoint exists,
    /// turns before the latest checkpoint are dropped from the projection (they
    /// are summarised by the checkpoint). The canonical chain is never mutated.
    var requestMessages: [ChatMessage] {
        if let idx = committed.lastIndex(where: { $0.isCheckpoint }) {
            return Array(committed[idx...])
        }
        return committed
    }

    // MARK: - Append-only writes (committed chain)

    func append(_ message: ChatMessage) {
        committed.append(message)
        envelope.updatedAt = Date()
        recompose()
    }

    func append(contentsOf messages: [ChatMessage]) {
        committed.append(contentsOf: messages)
        envelope.updatedAt = Date()
        recompose()
    }

    /// Commits a final tool result to the chain. If a committed message for the
    /// same `toolCallId` already exists it is replaced; otherwise it is appended.
    /// This collapses the case where a tool result is delivered both via the
    /// streaming progress closure and the returned result collection, ensuring each
    /// tool invocation is recorded exactly once. Distinct calls remain append-only.
    func commitToolResult(_ message: ChatMessage) {
        guard message.isToolExecution,
              let toolCallId = message.toolCallId, !toolCallId.isEmpty else {
            committed.append(message)
            envelope.updatedAt = Date()
            recompose()
            return
        }
        if let index = committed.lastIndex(where: { $0.toolCallId == toolCallId }) {
            committed[index] = message
        } else {
            committed.append(message)
        }
        envelope.updatedAt = Date()
        recompose()
    }

    // MARK: - Ephemeral draft (streaming) — UI only, not in the chain

    func setDraft(_ message: ChatMessage) {
        draft = message
        recompose()
    }

    func updateDraft(content: String) {
        guard var d = draft else { return }
        d = ChatMessage(
            id: d.id,
            role: d.role,
            content: content,
            timestamp: d.timestamp,
            context: ChatMessageContentContext(reasoning: d.reasoning, codeContext: d.codeContext),
            tool: ChatMessageToolContext(
                toolName: d.toolName,
                toolStatus: d.toolStatus,
                target: ToolInvocationTarget(targetFile: d.targetFile ?? "", toolCallId: d.toolCallId ?? "")
            ),
            isDraft: true
        )
        draft = d
        recompose()
    }

    func commitDraft() {
        guard let d = draft else { return }
        committed.append(d)
        draft = nil
        envelope.updatedAt = Date()
        recompose()
    }

    func clearDraft() {
        draft = nil
        recompose()
    }

    func getDraftMessage(id: UUID) -> ChatMessage? {
        draft?.id == id ? draft : nil
    }

    // MARK: - Ephemeral live tool status — UI only, overlay on committed

    func setLiveToolStatus(toolCallId: String, status: ToolExecutionStatus) {
        liveToolStatus[toolCallId] = status
        recompose()
    }

    func clearLiveToolStatus(toolCallId: String) {
        liveToolStatus.removeValue(forKey: toolCallId)
        recompose()
    }

    /// In-progress tool execution message (executing). Ephemeral — shown in the
    /// UI while the tool runs, never committed to the chain.
    func setLiveToolMessage(_ message: ChatMessage) {
        guard let tc = message.toolCallId else { return }
        liveToolMessages[tc] = message
        recompose()
    }

    func clearLiveToolMessage(_ toolCallId: String) {
        liveToolMessages.removeValue(forKey: toolCallId)
        recompose()
    }

    /// Reflect a user cancellation on an in-flight (ephemeral) tool message.
    /// The committed chain is never edited — only the live overlay / live message.
    func cancelLiveTool(toolCallId: String, content: String) {
        if let msg = liveToolMessages[toolCallId] {
            let updated = ChatMessage(
                id: msg.id,
                role: msg.role,
                content: content,
                timestamp: msg.timestamp,
                context: ChatMessageContentContext(reasoning: msg.reasoning, codeContext: msg.codeContext),
                billing: msg.billing,
                tool: ChatMessageToolContext(
                    toolName: msg.toolName,
                    toolStatus: .failed,
                    target: ToolInvocationTarget(targetFile: msg.targetFile ?? "", toolCallId: toolCallId)
                )
            )
            liveToolMessages[toolCallId] = updated
        }
        liveToolStatus[toolCallId] = .failed
        recompose()
    }

    // MARK: - Context management (append-only, never edits a node)

    /// Append a compaction checkpoint summarizing earlier turns. The canonical
    /// chain is untouched; `requestMessages` folds pre-checkpoint turns.
    func compact(summary: String) {
        let checkpoint = ChatMessage(
            role: .system,
            content: summary,
            isCheckpoint: true
        )
        committed.append(checkpoint)
        envelope.updatedAt = Date()
        recompose()
    }

    // MARK: - Session lifecycle

    /// Load a restored session's committed turns. This is a load (not an edit of
    /// existing nodes), used by session restore. The chain becomes `messages`.
    func restoreCommitted(_ messages: [ChatMessage]) {
        committed = messages
        draft = nil
        liveToolMessages.removeAll()
        liveToolStatus.removeAll()
        recompose()
    }

    func clearConversation() {
        committed.removeAll()
        draft = nil
        liveToolStatus.removeAll()
        liveToolMessages.removeAll()
        recompose()
    }

    func startNewConversation(projectRoot: URL) -> (previousConversationId: String, newConversationId: String) {
        let old = envelope.id.uuidString
        envelope = ConversationEnvelope()
        committed.removeAll()
        draft = nil
        liveToolStatus.removeAll()
        liveToolMessages.removeAll()
        recompose()
        return (old, envelope.id.uuidString)
    }

    func switchConversation(to newConversationId: String, projectRoot: URL) {
        envelope = ConversationEnvelope(id: UUID(uuidString: newConversationId) ?? UUID())
        committed.removeAll()
        draft = nil
        liveToolStatus.removeAll()
        liveToolMessages.removeAll()
        recompose()
    }

    func updateSubject(_ subject: String) {
        envelope.subject = subject
        envelope.updatedAt = Date()
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
        if shouldStartConversationLog {
            Task.detached(priority: .utility) {
                await onStartConversation(self.envelope.id.uuidString, "", newRoot.path)
            }
        }
    }

    // MARK: - Private

    private func recompose() {
        var out = committed
        if !liveToolMessages.isEmpty {
            out.append(contentsOf: liveToolMessages.values)
        }
        if !liveToolStatus.isEmpty {
            out = out.map { msg in
                guard let tc = msg.toolCallId, let st = liveToolStatus[tc] else { return msg }
                var m = msg
                m.toolStatus = st
                return m
            }
        }
        if let draft {
            out.append(draft)
        }
        messages = out
    }
}
