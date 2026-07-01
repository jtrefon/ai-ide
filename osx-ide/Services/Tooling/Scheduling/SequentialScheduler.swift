import Foundation
actor SequentialScheduler { let gov: ResourceGovernor; let exec: ToolExecutor; init(gov: ResourceGovernor,exec: ToolExecutor){self.gov = gov;self.exec = exec}
    func schedule(calls:[ParsedToolCall],ctx: ExecutionContext)async->[ToolResult]{var r:[ToolResult]=[];let sd = Date()
        for c in calls{let fb = await gov.exec(req: ToolExecutionRequest(toolName: c.toolName,arguments: c.arguments,context: ctx),exec: exec);r.append(.success(toolCall: c,feedback: fb,startedAt: sd))};return r}
}
