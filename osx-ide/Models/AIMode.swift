import Foundation

public enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat = "Chat"
    case coder = "Coder"
    case agent = "Agent"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .chat:
            return "Read-only conversation. AI can answer questions but cannot modify anything."
        case .coder:
            return "Focused coding with tools. AI can read, write, search, and edit files to complete specific tasks."
        case .agent:
            return "Full autonomy. AI can plan, execute multi-step tasks, and use advanced tooling autonomously."
        }
    }

    public var icon: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .coder:
            return "hammer"
        case .agent:
            return "gearshape.2"
        }
    }

    /// Whether this mode uses the new Phase 1 architecture (CoderOrchestrator)
    /// vs the old ToolLoopHandler architecture.
    var usesNewArchitecture: Bool {
        self == .coder
    }

    public func allowedTools(from allTools: [AITool]) -> [AITool] {
        switch self {
        case .chat:
            return []
        case .coder:
            // Coder mode filters out replace_in_file — use patch_file instead
            return allTools.filter { $0.name != "replace_in_file" }
        case .agent:
            return allTools
        }
    }
}
