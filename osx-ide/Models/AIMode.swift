import Foundation

public enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case chat = "Chat"
    case coder = "Coder"
    case agent = "Agent"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .chat:
            return "Read-only. Can search and browse — but cannot write, edit, or run terminal commands."
        case .coder:
            return "Full-access pair programming. All tools, all rights, guided by your direction. The primary mode."
        case .agent:
            return "Autonomous swarm execution (future). Parallel agent spawning for concurrent progress. Future work."
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

    /// Whether this mode uses the coder pipeline (ToolLoopHandler) vs a different architecture.
    var usesNewArchitecture: Bool {
        self == .coder
    }

    /// Capability gate — NOT a prompt/toolset selector.
    ///
    /// Architectural invariant: modes are only prompts that advertise different
    /// toolsets (`allowedTools(from:)`) and system prompts (`SystemPromptAssembler`).
    /// The agent is mode-agnostic — it runs the same tool loop, finalization,
    /// continuation, recovery, and QA review under every mode. Gating any of
    /// that machinery on `mode == .agent` was a crack: the agent's actual
    /// runtime mode (`.chat`, which carries the read toolset) was excluded,
    /// discarding tool results and disabling QA for the one mode in use.
    ///
    /// Capability checks MUST go through `isAgentic`, never through a raw
    /// `mode == .agent` comparison.
    public var isAgentic: Bool {
        // Every mode is the same agent with a different toolset.
        true
    }

    /// Three distinct modes for three distinct purposes.
    /// - chat:  Read-only conversation. No file alterations, no terminal execution.
    /// - coder: Full tool access + structured planning. The primary mode. Competing with Cursor, Windsurf, Code Pilot.
    /// - agent: Future autonomous swarm execution. Parallel agent spawning. Not yet implemented.
    public func allowedTools(from allTools: [AITool]) -> [AITool] {
        switch self {
        case .chat:
            // Chat can use everything EXCEPT mutation tools (no writes to your project)
            return allTools.filter { tool in
                switch tool.name {
                case "write", "rm", "edit", "bash",
                     "write_file", "write_files", "create_file", "delete_file",
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
