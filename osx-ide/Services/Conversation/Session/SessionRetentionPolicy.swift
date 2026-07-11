import Foundation

// MARK: - L4 Session Retention (Strategy)

/// Context provided to a `SessionRetentionPolicy` for eviction decisions.
public struct SessionRetentionContext: Sendable {
    public let records: [SessionRecord]
    public let activeSessionId: String
    public let now: Date

    public init(records: [SessionRecord], activeSessionId: String, now: Date) {
        self.records = records
        self.activeSessionId = activeSessionId
        self.now = now
    }
}

/// A snapshot of a session's state for the retention policy to evaluate.
public struct SessionRecord: Sendable, Equatable {
    public let sessionId: String
    public let closedAt: Date
    public let isActive: Bool
    public let turnCount: Int?

    public init(sessionId: String, closedAt: Date, isActive: Bool, turnCount: Int? = nil) {
        self.sessionId = sessionId
        self.closedAt = closedAt
        self.isActive = isActive
        self.turnCount = turnCount
    }
}

/// Governs in-memory eviction of closed sessions. On-disk NDJSON is never
/// deleted — retention only controls whether the in-memory `ConversationStreamStore`
/// is kept (re-opening from disk is always possible within the retention window).
public protocol SessionRetentionPolicy: Sendable {
    /// Returns the set of session IDs to evict from memory.
    func sessionsToEvict(_ context: SessionRetentionContext) -> Set<String>
}

/// Retains each closed session for up to `maxAge` seconds since close.
/// Active sessions are never evicted.
public struct TimeBasedRetention: SessionRetentionPolicy {
    public let maxAge: TimeInterval

    public init(maxAge: TimeInterval) {
        self.maxAge = maxAge
    }

    public func sessionsToEvict(_ context: SessionRetentionContext) -> Set<String> {
        Set(
            context.records
                .filter { !$0.isActive }
                .filter { context.now.timeIntervalSince($0.closedAt) >= maxAge }
                .map { $0.sessionId }
        )
    }
}

/// Retains only the `maxRetained` most-recently-closed sessions (by `closedAt`).
/// Active sessions are never evicted.
public struct CountBasedRetention: SessionRetentionPolicy {
    public let maxRetained: Int

    public init(maxRetained: Int) {
        self.maxRetained = maxRetained
    }

    public func sessionsToEvict(_ context: SessionRetentionContext) -> Set<String> {
        let closedRecords = context.records
            .filter { !$0.isActive }
            .sorted { $0.closedAt > $1.closedAt }
        if closedRecords.count <= maxRetained { return [] }
        return Set(closedRecords.dropFirst(maxRetained).map { $0.sessionId })
    }
}
