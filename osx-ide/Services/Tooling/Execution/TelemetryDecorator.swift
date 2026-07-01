import Foundation
struct TelemetryDecorator: ToolExecutor { let inner: ToolExecutor
    func execute(request: ToolExecutionRequest) async -> ToolFeedback {
        let s = Date(); let r = await inner.execute(request: request); print("[TOOL]", request.toolName, r.status.rawValue, Int(Date().timeIntervalSince(s)*1000), "ms"); return r
    }
}
