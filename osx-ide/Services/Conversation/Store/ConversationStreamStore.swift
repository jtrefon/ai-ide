import Foundation

// MARK: - L5 Persistence (Write Model) — single writer, append-only

/// Contract for the durable, append-only conversation log. The only type permitted
/// to add turns to a session's stream.
public protocol ConversationLogRepository: Sendable {
    /// Appends a turn, assigning `seq` (monotonic) and `ts`. Acknowledges only after
    /// the record is fsynced to disk.
    func append(_ event: TurnEvent) async throws -> Turn
    /// Returns a copy of all turns in `seq` order. Never exposes a mutable handle.
    func allTurns() async -> [Turn]
    /// Returns turns with `seq > given` in `seq` order.
    func turns(after seq: UInt64) async -> [Turn]
    /// Returns the most recent `checkpoint` turn, if any.
    func latestCheckpoint() async -> Turn?
}

public enum ConversationLogStoreError: Error {
    case encodingFailed
    case fileUnavailable(URL)
}

/// Append-only, NDJSON-backed conversation journal. One instance per conversation.
/// There is intentionally NO remove / replace / update API — immutability is enforced
/// by the absence of such methods (Invariant D2).
public actor ConversationStreamStore: ConversationLogRepository {
    private var turns: [Turn]
    private var nextSeq: UInt64
    private let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL

        if !FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path) {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        var loaded: [Turn] = []
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty,
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
                if let turn = try? JSONDecoder().decode(Turn.self, from: Data(line.utf8)) {
                    loaded.append(turn)
                }
            }
        }
        loaded.sort { $0.meta.seq < $1.meta.seq }
        self.turns = loaded
        self.nextSeq = (loaded.last?.meta.seq).map { $0 + 1 } ?? 0
    }

    public func append(_ event: TurnEvent) async throws -> Turn {
        let seq = nextSeq
        nextSeq += 1

        let meta = TurnMeta(
            id: UUID(),
            seq: seq,
            ts: Date(),
            producer: event.producer,
            sessionId: event.sessionId,
            conversationId: event.conversationId
        )
        let turn = Turn(meta: meta, content: event.content)
        turns.append(turn)

        guard let bytes = ((String(data: try JSONEncoder().encode(turn), encoding: .utf8) ?? "") + "\n").data(using: .utf8) else {
            throw ConversationLogStoreError.encodingFailed
        }

        // Open, append at end, fsync. No persistent handle → no lifetime hazards.
        let fh = try FileHandle(forWritingTo: fileURL)
        try fh.seekToEnd()
        fh.write(bytes)
        fh.synchronizeFile()
        fh.closeFile()

        return turn
    }

    public func allTurns() async -> [Turn] { turns }

    public func turns(after seq: UInt64) async -> [Turn] {
        turns.filter { $0.meta.seq > seq }
    }

    public func latestCheckpoint() async -> Turn? {
        turns.reversed().first { turn in
            if case .checkpoint = turn.content { return true }
            return false
        }
    }
}
