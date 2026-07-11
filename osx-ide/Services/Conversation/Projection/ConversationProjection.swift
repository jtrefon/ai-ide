import Foundation

// MARK: - L3 Projections (CQRS read models)

/// Role of a message in a projected prompt.
public enum ProjectedMessageRole: String, Sendable, CaseIterable {
    case system, user, assistant, tool
}

/// A single message produced by a `ConversationProjection`.
/// `cacheBreakpointAfter` flags the ideal position for provider prefix-caching
/// (e.g., Anthropic's `cache_control: {"type": "ephemeral"}`, or OpenAI's
/// automatic prefix cache).  Setting this on the first user message after
/// the immutable system+tool block keeps the prompt prefix stable across turns.
public struct ProjectedMessage: Sendable, Equatable {
    public let role: ProjectedMessageRole
    public let content: String
    public let cacheBreakpointAfter: Bool

    public init(role: ProjectedMessageRole, content: String, cacheBreakpointAfter: Bool = false) {
        self.role = role
        self.content = content
        self.cacheBreakpointAfter = cacheBreakpointAfter
    }
}

/// Immutable context supplied to every `ConversationProjection.project` call.
public struct ProjectionContext: Sendable {
    /// The system prompt (instructions, persona, formatting rules).
    public let systemPrompt: String
    /// Tool definitions (JSON schema or markdown) appended to the system block.
    public let toolDefinitions: String
    /// If true, mark the first user message after the system block with
    /// `cacheBreakpointAfter = true`.
    public let markCacheBreakpoint: Bool

    public init(systemPrompt: String, toolDefinitions: String = "", markCacheBreakpoint: Bool = true) {
        self.systemPrompt = systemPrompt
        self.toolDefinitions = toolDefinitions
        self.markCacheBreakpoint = markCacheBreakpoint
    }
}

// MARK: - Projection protocol

/// A pure function from (turns, context) → typed output.
/// Concrete implementations each serve one consumer (Prompt, UI, Telemetry, Vector).
public protocol ConversationProjection<Output>: Sendable {
    associatedtype Output: Sendable
    /// Build the projection. **Must** be a deterministic function of the inputs;
    /// same `(turns, context)` must always produce the same `Output`.
    func project(_ turns: [Turn], context: ProjectionContext) async -> Output
}
