import Foundation

// MARK: - L4 Session Registry — owns one ConversationStreamStore per session

/// Interface for session-scoped conversation stream management.
public protocol SessionRegistryProtocol: Sendable {
    func currentSessionId() async -> String
    func activeStore() async -> ConversationStreamStore
    func store(forSessionId id: String) async -> ConversationStreamStore?
    func startNewSession(with sessionId: String) async
    func switchSession(to sessionId: String) async
    func closeSession(_ sessionId: String) async
    /// Force an eviction cycle (caller can control `now` for deterministic testing).
    func prune(now: Date) async
}

/// Manages a key-value mapping of `sessionId → ConversationStreamStore`.
///
/// **Isolation:** each session is an independent stream; switching sessions changes
/// the active pointer without copying or altering either stream (Invariant D4).
///
/// **Durability:** on-disk NDJSON is the durable source of truth. In-memory stores
/// are cached for performance. `SessionRetentionPolicy` governs eviction from memory;
/// disk files survive within the retention window ("bank-solid").
///
/// **Integration:** `SessionManager` (existing UI-layer tab/snapshot owner) drives
/// lifecycle; this registry mirrors the session id space and owns the data-layer stores.
/// Phase 5 wires `SessionManager.startNew/switchTo/close` → registry calls.
public actor SessionRegistry: SessionRegistryProtocol {
    private let projectRoot: URL
    private var stores: [String: ConversationStreamStore] = [:]
    private var activeSessionId: String
    private var closedAt: [String: Date] = [:]
    private let retention: SessionRetentionPolicy

    public init(
        projectRoot: URL,
        initialSessionId: String,
        retention: SessionRetentionPolicy
    ) {
        self.projectRoot = projectRoot
        self.activeSessionId = initialSessionId
        self.retention = retention
    }

    // MARK: - Public

    public func currentSessionId() async -> String { activeSessionId }

    /// Returns the store for the active session, creating it on demand.
    public func activeStore() async -> ConversationStreamStore {
        await ensureStore(for: activeSessionId)
    }

    /// Returns a store for any session (rehydrates from disk if evicted).
    /// Returns `nil` only if the store cannot be created.
    public func store(forSessionId id: String) async -> ConversationStreamStore? {
        if let existing = stores[id] { return existing }
        do {
            let store = try ConversationStreamStore(fileURL: url(for: id))
            stores[id] = store
            return store
        } catch {
            return nil
        }
    }

    /// Create a brand-new session and make it active.
    public func startNewSession(with sessionId: String) async {
        _ = try? await store(forSessionId: sessionId)  // ensures a fresh store is created
        activeSessionId = sessionId
        closedAt.removeValue(forKey: sessionId)
    }

    /// Switch the active pointer to an existing session. Creates the store if needed.
    public func switchSession(to sessionId: String) async {
        _ = try? await store(forSessionId: sessionId)
        activeSessionId = sessionId
        closedAt.removeValue(forKey: sessionId)
    }

    /// Mark a session as closed. It becomes eligible for eviction according to the
    /// retention policy. Active sessions may be closed; the active pointer stays on it
    /// until `switchSession` is called.
    public func closeSession(_ sessionId: String) async {
        closedAt[sessionId] = Date()
        if sessionId != activeSessionId {
            await prune(now: Date())
        }
    }

    /// Evaluate the retention policy and evict sessions that should no longer be
    /// cached in memory. The on-disk NDJSON is never deleted — re-opening is always
    /// possible via `store(forSessionId:)`.
    public func prune(now: Date) async {
        let records = closedAt.map { id, closed in
            SessionRecord(sessionId: id, closedAt: closed, isActive: id == activeSessionId, turnCount: nil)
        }
        let context = SessionRetentionContext(records: Array(records), activeSessionId: activeSessionId, now: now)
        let toEvict = retention.sessionsToEvict(context)
        for id in toEvict {
            stores[id] = nil
            closedAt.removeValue(forKey: id)
        }
    }

    // MARK: - Private

    /// Path: `<projectRoot>/.ide/chat/<sessionId>/turns.ndjson`
    private func url(for sessionId: String) -> URL {
        projectRoot
            .appendingPathComponent(AppConstantsFileSystem.projectDirName, isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
            .appendingPathComponent("turns.ndjson")
    }

    /// Get or create the store for a session id.
    private func ensureStore(for sessionId: String) -> ConversationStreamStore {
        if let existing = stores[sessionId] { return existing }
        // A new store is created even if the file doesn't exist yet;
        // ConversationStreamStore.init handles the "file not found" case.
        guard let store = try? ConversationStreamStore(fileURL: url(for: sessionId)) else {
            // Fallback: create empty store at the correct path.
            let store = try! ConversationStreamStore(fileURL: url(for: sessionId))
            stores[sessionId] = store
            return store
        }
        stores[sessionId] = store
        return store
    }
}
