import Foundation

/// Wraps an OpenAI-format tool schema as an AITool for the existing API.
/// The existing AITool protocol requires execute(), but we only use this for
/// schema transport — tool execution is handled by our ToolExecutor chain.
final class DynamicAITool: @unchecked Sendable, AITool {
    let name: String
    let description: String
    let parameters: [String: Any]

    init?(from openAITool: [String: Any]) {
        guard let type = openAITool["type"] as? String, type == "function",
              let fn = openAITool["function"] as? [String: Any],
              let name = fn["name"] as? String,
              let desc = fn["description"] as? String else {
            return nil
        }
        self.name = name
        self.description = desc
        self.parameters = fn["parameters"] as? [String: Any] ?? [:]
    }

    func execute(arguments: ToolArguments) async throws -> String {
        throw AppError.aiServiceError("DynamicAITool cannot be executed directly. Use ToolExecutor chain instead.")
    }
}

/// Bridge adapter: wraps the existing AIService into our new AIServiceProtocol.
/// Converts tool schemas from our format to the existing AITool format.
private struct AIServiceBridge: AIServiceProtocol {
    let wrapped: any AIService

    func complete(msgs: [ChatMessage], tools: [[String: Any]]?) async throws -> AIServResp {
        // Convert our OpenAI-format tool schemas to the existing [AITool] format
        let aitools: [AITool]? = tools?.compactMap { DynamicAITool(from: $0) }

        let request = AIServiceHistoryRequest(
            messages: msgs,
            context: nil,
            tools: aitools,
            mode: .agent,
            projectRoot: nil
        )
        let response = try await wrapped.sendMessage(request)
        return AIServResp(content: response.content, toolCalls: response.toolCalls)
    }
}

extension DependencyContainer {
    func makeToolingStack() -> ToolingStack {
        let r = ToolRegistry()
        ToolRegistrar.registerAll(in: r, pathValidator: nil, index: nil, projectRoot: nil)
        let l = FileAccessLedger()
        let g = ToolLoopGuard()
        let gov = ResourceGovernor()
        let re = RealToolExecutor(registry: r)
        let sd = SandboxDecorator(inner: re, ledger: l)
        let td = TelemetryDecorator(inner: sd)
        let sc = SequentialScheduler(gov: gov, exec: td)
        let ad = OpenRouterToolAdapter()
        let bridge = AIServiceBridge(wrapped: aiService)
        let or = CoderOrchestrator(reg: r, sch: sc, adp: ad, lg: g, led: l, ai: bridge)
        return ToolingStack(registry: r, orchestrator: or, scheduler: sc, governor: gov, executor: td, adapter: ad)
    }
}
