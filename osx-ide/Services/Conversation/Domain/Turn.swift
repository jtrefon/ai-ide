import Foundation

// MARK: - L6 Domain Model (zero dependencies)

/// Who produced a turn. Producers only emit events; they never mutate the log.
public enum TurnProducer: String, Sendable, Codable, CaseIterable {
    case user
    case agent
    case tool
    case planner
    case system
}

/// Lightweight, log-friendly summary of a tool call. Raw argument payloads are
/// never stored in the log head — only a digest.
public struct ToolCallSummary: Sendable, Codable, Equatable {
    public let toolCallId: String
    public let name: String
    public let argumentsDigest: String

    public init(toolCallId: String, name: String, argumentsDigest: String) {
        self.toolCallId = toolCallId
        self.name = name
        self.argumentsDigest = argumentsDigest
    }
}

/// Lightweight, log-friendly summary of a tool result. Full payload lives in the
/// store and is referenced by `outputRef` — never inlined into the turn.
public struct ToolResultSummary: Sendable, Codable, Equatable {
    public let toolCallId: String
    public let name: String
    public let status: String
    public let targetFile: String?
    public let outputRef: String?

    public init(
        toolCallId: String,
        name: String,
        status: String,
        targetFile: String? = nil,
        outputRef: String? = nil
    ) {
        self.toolCallId = toolCallId
        self.name = name
        self.status = status
        self.targetFile = targetFile
        self.outputRef = outputRef
    }
}

/// The payload of a single turn. Immutable once written.
///
/// `Codable` is implemented manually (not synthesized) because Swift's synthesized
/// encoder emits single-associated-value cases as `{"userText":{"_0":"..."}}` while
/// its decoder expects `{"userText":"..."}` — a round-trip mismatch that silently
/// drops turns on reload. The manual form below is stable and symmetric.
public enum TurnContent: Sendable, Equatable {
    case userText(String)
    case assistant(text: String, reasoning: String?, toolCalls: [ToolCallSummary])
    case toolCall(ToolCallSummary)
    case toolResult(ToolResultSummary)
    case systemText(String)
    case plan(String)
    /// Compressed summary of earlier turns. Appended for compaction; the canonical
    /// log is never edited.
    case checkpoint(String)
}

extension TurnContent: Codable {
    private enum Key: String, CodingKey {
        case kind, value, text, reasoning, toolCalls, toolCall, toolResult
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .userText(let v):
            try c.encode("userText", forKey: .kind); try c.encode(v, forKey: .value)
        case .assistant(let text, let reasoning, let toolCalls):
            try c.encode("assistant", forKey: .kind)
            try c.encode(text, forKey: .text)
            try c.encode(reasoning, forKey: .reasoning)
            try c.encode(toolCalls, forKey: .toolCalls)
        case .toolCall(let v):
            try c.encode("toolCall", forKey: .kind); try c.encode(v, forKey: .toolCall)
        case .toolResult(let v):
            try c.encode("toolResult", forKey: .kind); try c.encode(v, forKey: .toolResult)
        case .systemText(let v):
            try c.encode("systemText", forKey: .kind); try c.encode(v, forKey: .value)
        case .plan(let v):
            try c.encode("plan", forKey: .kind); try c.encode(v, forKey: .value)
        case .checkpoint(let v):
            try c.encode("checkpoint", forKey: .kind); try c.encode(v, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "userText":
            self = .userText(try c.decode(String.self, forKey: .value))
        case "assistant":
            self = .assistant(
                text: try c.decode(String.self, forKey: .text),
                reasoning: try c.decodeIfPresent(String.self, forKey: .reasoning),
                toolCalls: try c.decode([ToolCallSummary].self, forKey: .toolCalls)
            )
        case "toolCall":
            self = .toolCall(try c.decode(ToolCallSummary.self, forKey: .toolCall))
        case "toolResult":
            self = .toolResult(try c.decode(ToolResultSummary.self, forKey: .toolResult))
        case "systemText":
            self = .systemText(try c.decode(String.self, forKey: .value))
        case "plan":
            self = .plan(try c.decode(String.self, forKey: .value))
        case "checkpoint":
            self = .checkpoint(try c.decode(String.self, forKey: .value))
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Unknown TurnContent kind")
            )
        }
    }
}

/// Identity, ordering, and provenance of a turn. Assigned by the store on append.
public struct TurnMeta: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let seq: UInt64
    public let ts: Date
    public let producer: TurnProducer
    public let sessionId: String
    public let conversationId: String

    public init(
        id: UUID,
        seq: UInt64,
        ts: Date,
        producer: TurnProducer,
        sessionId: String,
        conversationId: String
    ) {
        self.id = id
        self.seq = seq
        self.ts = ts
        self.producer = producer
        self.sessionId = sessionId
        self.conversationId = conversationId
    }
}

/// An immutable, append-only record in the conversation stream.
public struct Turn: Identifiable, Sendable, Codable, Equatable {
    public let meta: TurnMeta
    public let content: TurnContent
    public var id: UUID { meta.id }

    public init(meta: TurnMeta, content: TurnContent) {
        self.meta = meta
        self.content = content
    }
}

/// What a producer emits. The store assigns `seq` and `ts`.
public struct TurnEvent: Sendable {
    public let producer: TurnProducer
    public let sessionId: String
    public let conversationId: String
    public let content: TurnContent

    public init(
        producer: TurnProducer,
        sessionId: String,
        conversationId: String,
        content: TurnContent
    ) {
        self.producer = producer
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.content = content
    }
}
