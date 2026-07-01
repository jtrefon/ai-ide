import Foundation

final class CoderOrchestrator: @unchecked Sendable {
    let reg: ToolRegistryProtocol
    let sch: SequentialScheduler
    let adp: ToolFormatAdapter
    let lg: ToolLoopGuard
    let led: FileAccessLedger
    let ai: AIServiceProtocol

    init(reg: ToolRegistryProtocol, sch: SequentialScheduler, adp: ToolFormatAdapter, lg: ToolLoopGuard, led: FileAccessLedger, ai: AIServiceProtocol) {
        self.reg = reg; self.sch = sch; self.adp = adp; self.lg = lg; self.led = led; self.ai = ai
    }

    func handle(req: SendReq, cid: String) async -> Resp {
        let tools = reg.tools(for: .coder)
        let enc = adp.encodeTools(tools)

        // Build a rich system prompt that explains tool usage
        let systemPrompt = buildSystemPrompt(tools: tools)
        var msgs = [ChatMessage(role: .system, content: systemPrompt)]
        msgs.append(ChatMessage(role: .user, content: req.msg))

        let ar: AIServResp
        do { ar = try await ai.complete(msgs: msgs, tools: enc) }
        catch { return .err("AI err: " + error.localizedDescription) }

        let calls: [ParsedToolCall]
        let resp = AIServiceResponse(content: ar.content, toolCalls: ar.toolCalls)
        do { calls = try adp.decodeCalls(from: resp) }
        catch { return .txt(ar.content ?? "") }

        if calls.isEmpty { return .txt(ar.content ?? "") }
        if await lg.shouldAbort(cid: cid, calls: calls) { return .txt("Loop aborted") }

        let tid = UUID().uuidString
        await led.startTurn(cid: cid, tid: tid)
        let ctx = ExecutionContext.coder(cid: cid, tid: tid, root: req.root)
        let results = await sch.schedule(calls: calls, ctx: ctx)
        await led.endTurn(tid)
        return .txt(adp.encodeBatch(results))
    }

    private func buildSystemPrompt(tools: [ToolDefinition]) -> String {
        var lines: [String] = [
            "You are a coding agent in Coder mode. You have tools available to complete coding tasks.",
            "",
            "## Tool Usage Rules",
            "- You MUST use tools to complete the user's request. Do NOT just describe what you'd do.",
            "- Read files before modifying them.",
            "- Use patch_file for targeted edits instead of write_file (more reliable).",
            "- Run tests to verify your changes work.",
            "",
            "## Available Tools",
        ]

        for tool in tools {
            lines.append("")
            lines.append("### \(tool.name)")
            lines.append(tool.description)
            if let guidance = tool.promptMaterial.guidance {
                if !guidance.whenToUse.isEmpty {
                    lines.append("When to use: \(guidance.whenToUse)")
                }
                if let notWhen = guidance.whenNotToUse, !notWhen.isEmpty {
                    lines.append("Do NOT use: \(notWhen)")
                }
            }
        }

        lines.append("")
        lines.append("## Response Format")
        lines.append("When you want to use a tool, output a structured tool call. The system will execute it and return the result.")
        lines.append("After all tool calls complete, provide a summary of what was done.")

        return lines.joined(separator: "\n")
    }
}

enum Resp: Sendable { case txt(String); case err(String) }
struct SendReq: Sendable { let msg: String; let root: URL; let messages: [ChatMessage] }
protocol AIServiceProtocol: Sendable { func complete(msgs: [ChatMessage], tools: [[String: Any]]?) async throws -> AIServResp }
struct AIServResp: Sendable { let content: String?; let toolCalls: [AIToolCall]? }
