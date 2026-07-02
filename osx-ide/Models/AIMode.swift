import Foundation

public enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat = "Chat"
    case coder = "Coder"
    case agent = "Agent"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .chat:
            return "Read-only conversation. AI can answer questions, search code, browse the web — but cannot write or edit files. For when you want AI perspective without changing anything."
        case .coder:
            return "Pair programming partner with full tool access. AI plans, decomposes tasks, executes edits, runs commands, searches the web — guided by your direction. Tracks progress across multi-step tasks."
        case .agent:
            return "Full autonomy assistant. AI plans top-level strategy, spawns sub-agents with dedicated prompts, delegates work across architecture/UI/testing/infra. For long-running, large-scale projects."
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

    /// Modes differ only in AUTONOMY LEVEL, not capability or tool access.
    /// - chat:  Read-only. No file writes. You do the coding, AI provides perspective. 1.5x-2x multiplier.
    /// - coder: Full tools + planning. AI takes direction, decomposes, executes, tracks. 3x-5x multiplier.
    /// - agent: Full tools + sub-agents + delegation. AI plans top-level, spawns specialists. 10x+ multiplier.
    public func allowedTools(from allTools: [AITool]) -> [AITool] {
        switch self {
        case .chat:
            // Chat can use everything EXCEPT mutation tools (no writes to your project)
            return allTools.filter { tool in
                switch tool.name {
                case "write_file", "write_files", "create_file", "delete_file",
                     "patch_file", "replace_in_file", "run_command":
                    return false
                default:
                    return true
                }
            }
        case .coder, .agent:
            // Coder and Agent have FULL tool access — same tools, different behavior
            return allTools
        }
    }
}
